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

unionid_query::queries! {
    schema "schema/copyboard.unid"

    query list_snippets_query {
        from snippets
        filter owner == $owner
        sort {-created_at, -id}
    }

    query latest_snippet_query {
        from snippets
        sort -id
        take 1
    }

    query insert_snippet_query {
        insert snippets $snippet
        returning
    }

    query delete_snippet_query {
        delete snippets
        filter id == $id
        filter owner == $owner
        returning id
    }
}

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
const DECLARATIVE_SCHEMA: &str = include_str!("../schema/copyboard.unid");
const PRE_AUTH_SCHEMA: &str = r#"struct Snippet {
  id: int
  content: text
  created_at: int
}
table snippets: Snippet {
  key id
}
create index snippets (created_at)
"#;

// Databases upgraded from the pre-auth schema have migration-established IDs
// and revision 2, so v0.9's declarative-schema macro cannot bind them safely.
// Keep the runtime path only for those existing databases.
const LEGACY_LIST: &str = "from snippets | filter owner == $owner | sort {-created_at, -id}";
const LEGACY_LATEST_ID: &str = "from snippets | sort -id | take 1";
const LEGACY_INSERT: &str = "insert snippets $snippet\nreturning";
const LEGACY_DELETE: &str =
    "delete snippets | filter id == $id | filter owner == $owner\nreturning id";

const TOKEN_TTL_SECONDS: i64 = 24 * 60 * 60;

type HmacSha256 = Hmac<Sha256>;

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
    typed_queries: bool,
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

    let typed_queries = macro_schema_matches(&engine);
    if !typed_queries && !logical_schema_matches(&engine)? {
        return Err(unionid::Error::new(
            "E_SCHEMA_CHANGED",
            "database schema does not match the Copyboard schema",
        ));
    }
    let now = unix_millis();
    let latest_id = if typed_queries {
        latest_snippet_query::latest_snippet_query(
            &mut engine,
            latest_snippet_query::LatestSnippetQueryParams,
        )?
        .map(|snippet| snippet.id)
    } else {
        engine
            .execute(LEGACY_LATEST_ID)
            .typed_rows::<Snippet>()?
            .into_iter()
            .next()
            .map(|snippet| snippet.id)
    };
    let next_id = latest_id.map_or(now, |id| now.max(id.saturating_add(1)));
    let state = AppState {
        engine: Arc::new(Mutex::new(engine)),
        typed_queries,
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
    if state.typed_queries {
        list_snippets_query::list_snippets_query(
            &mut engine,
            list_snippets_query::ListSnippetsQueryParams { owner },
        )
        .map(|rows| Json(rows.into_iter().map(Snippet::from).collect()))
        .map_err(internal_error)
    } else {
        engine
            .execute_with_params(
                LEGACY_LIST,
                BTreeMap::from([("owner".into(), Value::Text(owner))]),
            )
            .typed_rows::<Snippet>()
            .map(Json)
            .map_err(internal_error)
    }
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
    let mut engine = state.engine.lock().await;
    let created = if state.typed_queries {
        let output = insert_snippet_query::insert_snippet_query(
            &mut engine,
            insert_snippet_query::InsertSnippetQueryParams {
                snippet: snippet.clone(),
            },
        )
        .map_err(internal_error)?;
        Snippet::from(output.rows)
    } else {
        let value = Value::from_serde(&snippet).map_err(internal_error)?;
        engine
            .execute_with_params(LEGACY_INSERT, BTreeMap::from([("snippet".into(), value)]))
            .typed_rows::<Snippet>()
            .map_err(internal_error)?
            .into_iter()
            .next()
            .ok_or_else(|| internal_error("UnionID returned no inserted row"))?
    };
    Ok((StatusCode::CREATED, Json(created)))
}

async fn delete_snippet(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(id): AxumPath<i64>,
) -> Result<StatusCode, (StatusCode, Json<ApiError>)> {
    let owner = authorize(&headers, &state)?;
    let mut engine = state.engine.lock().await;
    let affected_rows = if state.typed_queries {
        delete_snippet_query::delete_snippet_query(
            &mut engine,
            delete_snippet_query::DeleteSnippetQueryParams { id, owner },
        )
        .map_err(internal_error)?
        .affected_rows
    } else {
        let response = engine.execute_with_params(
            LEGACY_DELETE,
            BTreeMap::from([
                ("id".into(), Value::Int(id)),
                ("owner".into(), Value::Text(owner)),
            ]),
        );
        if !response.ok {
            return Err(internal_error(response.message));
        }
        response.affected_rows.unwrap_or_default()
    };
    match affected_rows {
        0 => Err((
            StatusCode::NOT_FOUND,
            Json(ApiError {
                error: "snippet not found".into(),
            }),
        )),
        _ => Ok(StatusCode::NO_CONTENT),
    }
}

fn macro_schema_matches(engine: &Engine) -> bool {
    let schema = engine.schema_info();
    schema.revision == list_snippets_query::LIST_SNIPPETS_QUERY_SCHEMA_REVISION
        && schema.hash == list_snippets_query::LIST_SNIPPETS_QUERY_SCHEMA_HASH
}

fn logical_schema_matches(engine: &Engine) -> Result<bool, unionid::Error> {
    let mut expected = Engine::memory();
    let response = expected.execute(DECLARATIVE_SCHEMA);
    if !response.ok {
        return Err(response.error.unwrap_or_else(|| {
            unionid::Error::new("E_SCHEMA", "failed to load the embedded Copyboard schema")
        }));
    }
    if engine.schema() == expected.schema() {
        return Ok(true);
    }

    let mut migrated = Engine::memory();
    for source in [PRE_AUTH_SCHEMA, AUTH_MIGRATION] {
        let response = migrated.execute(source);
        if !response.ok {
            return Err(response.error.unwrap_or_else(|| {
                unionid::Error::new(
                    "E_SCHEMA",
                    "failed to load a Copyboard compatibility schema",
                )
            }));
        }
    }
    Ok(engine.schema() == migrated.schema())
}

impl From<list_snippets_query::ListSnippetsQueryRow> for Snippet {
    fn from(row: list_snippets_query::ListSnippetsQueryRow) -> Self {
        Self {
            id: row.id,
            content: row.content,
            created_at: row.created_at,
            owner: row.owner,
        }
    }
}

impl From<insert_snippet_query::InsertSnippetQueryRow> for Snippet {
    fn from(row: insert_snippet_query::InsertSnippetQueryRow) -> Self {
        Self {
            id: row.id,
            content: row.content,
            created_at: row.created_at,
            owner: row.owner,
        }
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
    if !valid_username(username) || expires_at.parse::<i64>().ok()? <= unix_seconds() {
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

    async fn create_as(service: Router, token: &str, content: &str) -> Snippet {
        let response = service
            .oneshot(
                Request::post("/api/snippets")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header(header::AUTHORIZATION, format!("Bearer {token}"))
                    .body(Body::from(
                        serde_json::json!({"content": content}).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::CREATED);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        serde_json::from_slice(&body).unwrap()
    }

    #[test]
    fn auth_configuration_and_tokens_reject_invalid_input() {
        let database = temp_database("auth-config");
        let secret = b"test-secret-at-least-32-bytes-long";

        let empty_users = app_with_auth(&database, BTreeMap::new(), secret.to_vec())
            .expect_err("empty users must fail");
        assert_eq!(empty_users.code, "E_AUTH_CONFIG");

        let short_secret = app_with_auth(&database, test_users(), b"too-short".to_vec())
            .expect_err("short secrets must fail");
        assert_eq!(short_secret.code, "E_AUTH_CONFIG");

        for invalid in ["alice", "al:password", "alice:", "invalid user:password"] {
            let error = parse_users(invalid).expect_err("invalid user configuration must fail");
            assert_eq!(error.code, "E_AUTH_CONFIG", "input: {invalid}");
        }

        let future = issue_token(secret, "alice", unix_seconds() + 60);
        assert_eq!(verify_token(secret, &future).as_deref(), Some("alice"));
        assert!(verify_token(secret, &format!("{future}x")).is_none());

        let expired = issue_token(secret, "alice", unix_seconds());
        assert!(verify_token(secret, &expired).is_none());
        assert!(!database.exists());
    }

    #[tokio::test]
    async fn health_and_auth_failures_are_cors_safe() {
        let database = temp_database("auth-http");
        let secret = b"test-secret-at-least-32-bytes-long".to_vec();
        let service = app_with_auth(&database, test_users(), secret.clone()).unwrap();

        let health = service
            .clone()
            .oneshot(Request::get("/health").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(health.status(), StatusCode::OK);
        assert_eq!(health.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN], "*");
        let body = to_bytes(health.into_body(), usize::MAX).await.unwrap();
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&body).unwrap(),
            serde_json::json!({"ok": true, "database": "unionid"})
        );

        for credentials in [
            serde_json::json!({"username": "alice", "password": "wrong"}),
            serde_json::json!({"username": "unknown", "password": "alice-pass"}),
        ] {
            let response = service
                .clone()
                .oneshot(
                    Request::post("/api/auth/login")
                        .header(header::CONTENT_TYPE, "application/json")
                        .body(Body::from(credentials.to_string()))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
            assert_eq!(response.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN], "*");
        }

        let unauthorized_tokens = [
            "not-a-token".to_owned(),
            issue_token(&secret, "alice", unix_seconds()),
            issue_token(&secret, "charlie", unix_seconds() + 60),
        ];
        for token in unauthorized_tokens {
            let response = service
                .clone()
                .oneshot(
                    Request::get("/api/snippets")
                        .header(header::AUTHORIZATION, format!("Bearer {token}"))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        }

        drop(service);
        let _ = std::fs::remove_file(database);
    }

    #[tokio::test]
    async fn snippet_input_is_trimmed_validated_and_stably_sorted() {
        let database = temp_database("validation");
        let service = app_with_auth(
            &database,
            test_users(),
            b"test-secret-at-least-32-bytes-long".to_vec(),
        )
        .unwrap();
        let token = login_as(service.clone(), "alice", "alice-pass").await;

        let blank = service
            .clone()
            .oneshot(
                Request::post("/api/snippets")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header(header::AUTHORIZATION, format!("Bearer {token}"))
                    .body(Body::from(r#"{"content":"  \n\t  "}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(blank.status(), StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(blank.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN], "*");

        let first = create_as(service.clone(), &token, "  first  \n").await;
        assert_eq!(first.content, "first");
        let second = create_as(service.clone(), &token, "second").await;
        assert!(second.id > first.id);

        let response = service
            .clone()
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
        assert_eq!(
            snippets
                .iter()
                .map(|snippet| snippet.id)
                .collect::<Vec<_>>(),
            vec![second.id, first.id]
        );

        drop(service);
        let _ = std::fs::remove_file(database);
    }

    #[tokio::test]
    async fn concurrent_creates_keep_ids_unique_and_data_isolated() {
        let database = temp_database("concurrent");
        let service = app_with_auth(
            &database,
            test_users(),
            b"test-secret-at-least-32-bytes-long".to_vec(),
        )
        .unwrap();
        let alice_token = login_as(service.clone(), "alice", "alice-pass").await;
        let bob_token = login_as(service.clone(), "bob", "bob-pass").await;

        let mut tasks = Vec::new();
        for index in 0..12 {
            let service = service.clone();
            let token = alice_token.clone();
            tasks.push(tokio::spawn(async move {
                create_as(service, &token, &format!("item-{index}")).await
            }));
        }

        let mut ids = std::collections::BTreeSet::new();
        for task in tasks {
            let snippet = task.await.unwrap();
            assert_eq!(snippet.owner, "alice");
            assert!(ids.insert(snippet.id), "duplicate id: {}", snippet.id);
        }
        assert_eq!(ids.len(), 12);

        let bob_response = service
            .clone()
            .oneshot(
                Request::get("/api/snippets")
                    .header(header::AUTHORIZATION, format!("Bearer {bob_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = to_bytes(bob_response.into_body(), usize::MAX)
            .await
            .unwrap();
        assert!(
            serde_json::from_slice::<Vec<Snippet>>(&body)
                .unwrap()
                .is_empty()
        );

        drop(service);
        let _ = std::fs::remove_file(database);
    }

    #[tokio::test]
    async fn reopening_database_continues_the_id_sequence() {
        let database = temp_database("id-reopen");
        let secret = b"test-secret-at-least-32-bytes-long".to_vec();
        let service = app_with_auth(&database, test_users(), secret.clone()).unwrap();
        let token = login_as(service.clone(), "alice", "alice-pass").await;
        let before_restart = create_as(service.clone(), &token, "before restart").await;
        drop(service);

        let reopened = app_with_auth(&database, test_users(), secret).unwrap();
        let token = login_as(reopened.clone(), "alice", "alice-pass").await;
        let after_restart = create_as(reopened.clone(), &token, "after restart").await;
        assert!(after_restart.id > before_restart.id);

        let response = reopened
            .clone()
            .oneshot(
                Request::get("/api/snippets")
                    .header(header::AUTHORIZATION, format!("Bearer {token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let snippets: Vec<Snippet> = serde_json::from_slice(&body).unwrap();
        assert_eq!(snippets.len(), 2);
        assert_eq!(snippets[0].id, after_restart.id);
        assert_eq!(snippets[1].id, before_restart.id);

        drop(reopened);
        let _ = std::fs::remove_file(database);
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

        let mut migrated = Engine::open_redb(&database).unwrap();
        let legacy_rows = migrated
            .execute("from snippets | filter owner == \"legacy\"")
            .typed_rows::<Snippet>()
            .unwrap();
        assert_eq!(legacy_rows.len(), 1);
        assert_eq!(legacy_rows[0].content, "old shared row");
        assert_eq!(legacy_rows[0].owner, "legacy");
        drop(migrated);

        let _ = std::fs::remove_file(database);
    }

    #[test]
    fn unexpected_schema_drift_is_rejected() {
        let database = temp_database("schema-drift");
        let service = app_with_auth(
            &database,
            test_users(),
            b"test-secret-at-least-32-bytes-long".to_vec(),
        )
        .unwrap();
        drop(service);

        let mut engine = Engine::open_redb(&database).unwrap();
        let changed = engine.execute("type Unexpected = text");
        assert!(changed.ok, "{}", changed.message);
        drop(engine);

        let error = app_with_auth(
            &database,
            test_users(),
            b"test-secret-at-least-32-bytes-long".to_vec(),
        )
        .expect_err("schema drift must fail closed");
        assert_eq!(error.code, "E_SCHEMA_CHANGED");

        let _ = std::fs::remove_file(database);
    }
}
