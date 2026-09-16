use std::collections::BTreeMap;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{Path as AxumPath, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::Response;
use axum::routing::{delete, get};
use axum::{Json, Router};
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use tokio::sync::Mutex;
use unionid::{Engine, Value};

const INITIAL_SCHEMA: &str = r#"migration m0001_initial {
  add struct Snippet {
    id: int
    content: text
    created_at: int
    owner: text
  }
  add table snippets: Snippet {
    key id
  }
  add index snippets.created_at
  add index snippets.owner
}
"#;

const AUTH_MIGRATION: &str = r#"migration m0002_auth {
  add field Snippet.owner: text = "legacy"
  add index snippets.owner
}
"#;

const LIST: &str = "from snippets | filter owner == $owner | sort -created_at";
const LATEST_ID: &str = "from snippets | sort -id | take 1";
const INSERT: &str = "insert snippets $snippet\nreturning";
const DELETE: &str = "delete snippets | filter id == $id | filter owner == $owner\nreturning id";
const TOKEN_TTL_SECONDS: i64 = 24 * 60 * 60;

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Snippet {
    pub id: i64,
    pub content: String,
    pub created_at: i64,
    pub owner: String,
}

#[derive(Debug, Deserialize)]
pub struct NewSnippet {
    pub content: String,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginResponse {
    pub token: String,
    pub username: String,
}

#[derive(Clone)]
pub struct AppState {
    engine: Arc<Mutex<Engine>>,
    ids: Arc<AtomicI64>,
    users: Arc<BTreeMap<String, String>>,
    secret: Arc<Vec<u8>>,
}

#[derive(Debug, Serialize)]
struct ApiError {
    error: String,
}

pub fn app(database_path: impl AsRef<Path>) -> Result<Router, unionid::Error> {
    let users_source = std::env::var("COPYBOARD_USERS")
        .map_err(|_| unionid::Error::new("E_AUTH_CONFIG", "COPYBOARD_USERS must be configured"))?;
    let users = parse_users(&users_source)?;
    let secret = std::env::var("COPYBOARD_SECRET")
        .map_err(|_| unionid::Error::new("E_AUTH_CONFIG", "COPYBOARD_SECRET must be configured"))?
        .into_bytes();
    app_with_auth(database_path, users, secret)
}

pub fn app_with_auth(
    database_path: impl AsRef<Path>,
    users: BTreeMap<String, String>,
    secret: Vec<u8>,
) -> Result<Router, unionid::Error> {
    if users.is_empty() || secret.len() < 32 {
        return Err(unionid::Error::new(
            "E_AUTH_CONFIG",
            "at least one user and a secret of 32 or more bytes are required",
        ));
    }
    let mut engine = Engine::open_redb(database_path.as_ref())?;
    if !engine.execute("from snippets | take 1").ok {
        let initialized = engine.execute(INITIAL_SCHEMA);
        if !initialized.ok {
            return Err(initialized
                .error
                .unwrap_or_else(|| unionid::Error::new("E_SCHEMA", initialized.message)));
        }
    } else if !engine.execute("from snippets | select owner | take 1").ok {
        let migrated = engine.execute(AUTH_MIGRATION);
        if !migrated.ok {
            return Err(migrated
                .error
                .unwrap_or_else(|| unionid::Error::new("E_SCHEMA", migrated.message)));
        }
    }

    let now = unix_millis();
    let next_id = engine
        .execute(LATEST_ID)
        .typed_rows::<Snippet>()?
        .into_iter()
        .next()
        .map_or(now, |snippet| now.max(snippet.id.saturating_add(1)));
    let state = AppState {
        engine: Arc::new(Mutex::new(engine)),
        ids: Arc::new(AtomicI64::new(next_id)),
        users: Arc::new(users),
        secret: Arc::new(secret),
    };

    Ok(Router::new()
        .route("/health", get(health))
        .route(
            "/api/auth/login",
            axum::routing::post(login).options(preflight),
        )
        .route(
            "/api/snippets",
            get(list_snippets).post(create_snippet).options(preflight),
        )
        .route(
            "/api/snippets/{id}",
            delete(delete_snippet).options(preflight),
        )
        .layer(middleware::from_fn(cors))
        .with_state(state))
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({"ok": true, "database": "unionid"}))
}

async fn login(
    State(state): State<AppState>,
    Json(input): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, (StatusCode, Json<ApiError>)> {
    let Some(expected) = state.users.get(&input.username) else {
        return Err(unauthorized());
    };
    if !password_matches(&state.secret, expected, &input.password) {
        return Err(unauthorized());
    }
    let token = issue_token(
        &state.secret,
        &input.username,
        unix_seconds() + TOKEN_TTL_SECONDS,
    );
    Ok(Json(LoginResponse {
        token,
        username: input.username,
    }))
}

async fn list_snippets(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<Snippet>>, (StatusCode, Json<ApiError>)> {
    let owner = authorize(&headers, &state)?;
    let mut engine = state.engine.lock().await;
    let response =
        engine.execute_with_params(LIST, BTreeMap::from([("owner".into(), Value::Text(owner))]));
    response
        .typed_rows::<Snippet>()
        .map(Json)
        .map_err(internal_error)
}

async fn create_snippet(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<NewSnippet>,
) -> Result<(StatusCode, Json<Snippet>), (StatusCode, Json<ApiError>)> {
    let owner = authorize(&headers, &state)?;
    let content = input.content.trim();
    if content.is_empty() {
        return Err((
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(ApiError {
                error: "content must not be empty".into(),
            }),
        ));
    }

    let snippet = Snippet {
        id: state.ids.fetch_add(1, Ordering::Relaxed),
        content: content.to_owned(),
        created_at: unix_millis(),
        owner,
    };
    let value = Value::from_serde(&snippet).map_err(internal_error)?;
    let mut engine = state.engine.lock().await;
    let response = engine.execute_with_params(INSERT, BTreeMap::from([("snippet".into(), value)]));
    let created = response
        .typed_rows::<Snippet>()
        .map_err(internal_error)?
        .into_iter()
        .next()
        .ok_or_else(|| internal_error("UnionID returned no inserted row"))?;
    Ok((StatusCode::CREATED, Json(created)))
}

async fn delete_snippet(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(id): AxumPath<i64>,
) -> Result<StatusCode, (StatusCode, Json<ApiError>)> {
    let owner = authorize(&headers, &state)?;
    let mut engine = state.engine.lock().await;
    let response = engine.execute_with_params(
        DELETE,
        BTreeMap::from([
            ("id".into(), Value::Int(id)),
            ("owner".into(), Value::Text(owner)),
        ]),
    );
    if !response.ok {
        return Err(internal_error(response.message));
    }
    match response.affected_rows {
        Some(0) => Err((
            StatusCode::NOT_FOUND,
            Json(ApiError {
                error: "snippet not found".into(),
            }),
        )),
        _ => Ok(StatusCode::NO_CONTENT),
    }
}

async fn preflight() -> StatusCode {
    StatusCode::NO_CONTENT
}

async fn cors(request: axum::extract::Request, next: Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    headers.insert(
        header::ACCESS_CONTROL_ALLOW_ORIGIN,
        HeaderValue::from_static("*"),
    );
    headers.insert(
        header::ACCESS_CONTROL_ALLOW_METHODS,
        HeaderValue::from_static("GET, POST, DELETE, OPTIONS"),
    );
    headers.insert(
        header::ACCESS_CONTROL_ALLOW_HEADERS,
        HeaderValue::from_static("authorization, content-type"),
    );
    response
}

fn unix_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is before Unix epoch")
        .as_millis() as i64
}

fn unix_seconds() -> i64 {
    unix_millis() / 1_000
}

fn parse_users(source: &str) -> Result<BTreeMap<String, String>, unionid::Error> {
    let mut users = BTreeMap::new();
    for entry in source.split(',').filter(|entry| !entry.trim().is_empty()) {
        let Some((username, password)) = entry.split_once(':') else {
            return Err(unionid::Error::new(
                "E_AUTH_CONFIG",
                "COPYBOARD_USERS entries must use username:password",
            ));
        };
        if !valid_username(username) || password.is_empty() {
            return Err(unionid::Error::new(
                "E_AUTH_CONFIG",
                "usernames must be 3-32 ASCII letters, digits, '_' or '-' and passwords cannot be empty",
            ));
        }
        users.insert(username.to_owned(), password.to_owned());
    }
    Ok(users)
}

fn valid_username(username: &str) -> bool {
    (3..=32).contains(&username.len())
        && username
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
}

fn password_matches(secret: &[u8], expected: &str, supplied: &str) -> bool {
    let mut expected_mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key size");
    expected_mac.update(expected.as_bytes());
    let expected_digest = expected_mac.finalize().into_bytes();

    let mut supplied_mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key size");
    supplied_mac.update(supplied.as_bytes());
    supplied_mac.verify_slice(&expected_digest).is_ok()
}

fn issue_token(secret: &[u8], username: &str, expires_at: i64) -> String {
    let payload = format!("{username}:{expires_at}");
    let encoded = URL_SAFE_NO_PAD.encode(payload.as_bytes());
    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key size");
    mac.update(encoded.as_bytes());
    let signature = URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes());
    format!("{encoded}.{signature}")
}

fn authorize(
    headers: &HeaderMap,
    state: &AppState,
) -> Result<String, (StatusCode, Json<ApiError>)> {
    let token = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .ok_or_else(unauthorized)?;
    let username = verify_token(&state.secret, token).ok_or_else(unauthorized)?;
    if state.users.contains_key(&username) {
        Ok(username)
    } else {
        Err(unauthorized())
    }
}

fn verify_token(secret: &[u8], token: &str) -> Option<String> {
    let (encoded, signature) = token.split_once('.')?;
    let signature = URL_SAFE_NO_PAD.decode(signature).ok()?;
    let mut mac = HmacSha256::new_from_slice(secret).ok()?;
    mac.update(encoded.as_bytes());
    mac.verify_slice(&signature).ok()?;

    let payload = String::from_utf8(URL_SAFE_NO_PAD.decode(encoded).ok()?).ok()?;
    let (username, expires_at) = payload.rsplit_once(':')?;
    if !valid_username(username) || expires_at.parse::<i64>().ok()? < unix_seconds() {
        return None;
    }
    Some(username.to_owned())
}

fn unauthorized() -> (StatusCode, Json<ApiError>) {
    (
        StatusCode::UNAUTHORIZED,
        Json(ApiError {
            error: "invalid username, password, or session".into(),
        }),
    )
}

fn internal_error(error: impl ToString) -> (StatusCode, Json<ApiError>) {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(ApiError {
            error: error.to_string(),
        }),
    )
}

#[cfg(test)]
mod tests {
    use axum::body::{Body, to_bytes};
    use axum::http::{Method, Request, header};
    use tower::ServiceExt;

    use super::*;

    fn temp_database(name: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "copyboard-lite-{name}-{}-{}.redb",
            std::process::id(),
            unix_millis()
        ))
    }

    fn test_users() -> BTreeMap<String, String> {
        BTreeMap::from([
            ("alice".into(), "alice-pass".into()),
            ("bob".into(), "bob-pass".into()),
        ])
    }

    async fn login_as(service: Router, username: &str, password: &str) -> String {
        let response = service
            .oneshot(
                Request::post("/api/auth/login")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({"username": username, "password": password}).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        serde_json::from_slice::<LoginResponse>(&body)
            .unwrap()
            .token
    }

    #[tokio::test]
    async fn snippets_round_trip_over_http_with_cors() {
        let database = temp_database("api");
        let secret = b"test-secret-at-least-32-bytes-long".to_vec();
        let service = app_with_auth(&database, test_users(), secret.clone()).unwrap();

        let preflight = service
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::OPTIONS)
                    .uri("/api/snippets")
                    .header(header::ORIGIN, "http://127.0.0.1:5173")
                    .header(header::ACCESS_CONTROL_REQUEST_METHOD, "POST")
                    .header(
                        header::ACCESS_CONTROL_REQUEST_HEADERS,
                        "authorization,content-type",
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(preflight.status(), StatusCode::NO_CONTENT);
        assert_eq!(
            preflight.headers()[header::ACCESS_CONTROL_ALLOW_METHODS],
            "GET, POST, DELETE, OPTIONS"
        );
        assert_eq!(
            preflight.headers()[header::ACCESS_CONTROL_ALLOW_HEADERS],
            "authorization, content-type"
        );

        let anonymous = service
            .clone()
            .oneshot(Request::get("/api/snippets").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(anonymous.status(), StatusCode::UNAUTHORIZED);

        let alice_token = login_as(service.clone(), "alice", "alice-pass").await;
        let bob_token = login_as(service.clone(), "bob", "bob-pass").await;

        let create = service
            .clone()
            .oneshot(
                Request::post("/api/snippets")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header(header::AUTHORIZATION, format!("Bearer {alice_token}"))
                    .body(Body::from(r#"{"content":"hello UnionID"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(create.status(), StatusCode::CREATED);
        assert_eq!(create.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN], "*");

        let list = service
            .clone()
            .oneshot(Request::get("/api/snippets").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(list.status(), StatusCode::UNAUTHORIZED);

        let alice_list = service
            .clone()
            .oneshot(
                Request::get("/api/snippets")
                    .header(header::AUTHORIZATION, format!("Bearer {alice_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(alice_list.status(), StatusCode::OK);
        let body = to_bytes(alice_list.into_body(), usize::MAX).await.unwrap();
        let snippets: Vec<Snippet> = serde_json::from_slice(&body).unwrap();
        assert_eq!(snippets.len(), 1);
        assert_eq!(snippets[0].content, "hello UnionID");
        assert_eq!(snippets[0].owner, "alice");
        let snippet_id = snippets[0].id;

        let bob_list = service
            .clone()
            .oneshot(
                Request::get("/api/snippets")
                    .header(header::AUTHORIZATION, format!("Bearer {bob_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(bob_list.status(), StatusCode::OK);
        let body = to_bytes(bob_list.into_body(), usize::MAX).await.unwrap();
        let bob_snippets: Vec<Snippet> = serde_json::from_slice(&body).unwrap();
        assert!(bob_snippets.is_empty());

        let forbidden_delete = service
            .oneshot(
                Request::delete(format!("/api/snippets/{snippet_id}"))
                    .header(header::AUTHORIZATION, format!("Bearer {bob_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(forbidden_delete.status(), StatusCode::NOT_FOUND);

        let reopened = app_with_auth(&database, test_users(), secret).unwrap();
        let alice_token = login_as(reopened.clone(), "alice", "alice-pass").await;
        let list = reopened
            .clone()
            .oneshot(
                Request::get("/api/snippets")
                    .header(header::AUTHORIZATION, format!("Bearer {alice_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = to_bytes(list.into_body(), usize::MAX).await.unwrap();
        let persisted: Vec<Snippet> = serde_json::from_slice(&body).unwrap();
        assert_eq!(persisted.len(), 1);

        let deleted = reopened
            .oneshot(
                Request::delete(format!("/api/snippets/{}", persisted[0].id))
                    .header(header::AUTHORIZATION, format!("Bearer {alice_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

        let _ = std::fs::remove_file(database);
    }

    #[tokio::test]
    async fn legacy_shared_rows_are_migrated_but_not_exposed() {
        let database = temp_database("legacy");
        let mut engine = Engine::open_redb(&database).unwrap();
        let setup = engine.execute(
            r#"struct Snippet {
  id: int
  content: text
  created_at: int
}
table snippets: Snippet {
  key id
}
create index snippets (created_at)
insert snippets {id: 1, content: "old shared row", created_at: 1}
"#,
        );
        assert!(setup.ok, "{}", setup.message);
        drop(engine);

        let service = app_with_auth(
            &database,
            test_users(),
            b"test-secret-at-least-32-bytes-long".to_vec(),
        )
        .unwrap();
        let token = login_as(service.clone(), "alice", "alice-pass").await;
        let response = service
            .oneshot(
                Request::get("/api/snippets")
                    .header(header::AUTHORIZATION, format!("Bearer {token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let snippets: Vec<Snippet> = serde_json::from_slice(&body).unwrap();
        assert!(snippets.is_empty());

        let _ = std::fs::remove_file(database);
    }
}
