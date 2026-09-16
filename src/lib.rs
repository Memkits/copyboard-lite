use std::collections::BTreeMap;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{Path as AxumPath, State};
use axum::http::{HeaderValue, StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::Response;
use axum::routing::{delete, get};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;
use unionid::{Engine, Value};

const SCHEMA: &str = r#"type Snippet =
  id int
  content text
  created_at int

table snippets Snippet
  key id

create index snippets (created_at)
"#;

const LIST: &str = "from snippets | sort -created_at";
const LATEST_ID: &str = "from snippets | sort -id | take 1";
const INSERT: &str = "insert snippets $snippet\nreturning";
const DELETE: &str = "delete snippets | filter id == $id\nreturning id";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Snippet {
    pub id: i64,
    pub content: String,
    pub created_at: i64,
}

#[derive(Debug, Deserialize)]
pub struct NewSnippet {
    pub content: String,
}

#[derive(Clone)]
pub struct AppState {
    engine: Arc<Mutex<Engine>>,
    ids: Arc<AtomicI64>,
}

#[derive(Debug, Serialize)]
struct ApiError {
    error: String,
}

pub fn app(database_path: impl AsRef<Path>) -> Result<Router, unionid::Error> {
    let mut engine = Engine::open_redb(database_path.as_ref())?;
    if !engine.execute("from snippets | take 1").ok {
        let initialized = engine.execute(SCHEMA);
        if !initialized.ok {
            return Err(initialized
                .error
                .unwrap_or_else(|| unionid::Error::new("E_SCHEMA", initialized.message)));
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
    };

    Ok(Router::new()
        .route("/health", get(health))
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

async fn list_snippets(
    State(state): State<AppState>,
) -> Result<Json<Vec<Snippet>>, (StatusCode, Json<ApiError>)> {
    let mut engine = state.engine.lock().await;
    let response = engine.execute(LIST);
    response
        .typed_rows::<Snippet>()
        .map(Json)
        .map_err(internal_error)
}

async fn create_snippet(
    State(state): State<AppState>,
    Json(input): Json<NewSnippet>,
) -> Result<(StatusCode, Json<Snippet>), (StatusCode, Json<ApiError>)> {
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
    AxumPath(id): AxumPath<i64>,
) -> Result<StatusCode, (StatusCode, Json<ApiError>)> {
    let mut engine = state.engine.lock().await;
    let response =
        engine.execute_with_params(DELETE, BTreeMap::from([("id".into(), Value::Int(id))]));
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
        HeaderValue::from_static("content-type"),
    );
    response
}

fn unix_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is before Unix epoch")
        .as_millis() as i64
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

    #[tokio::test]
    async fn snippets_round_trip_over_http_with_cors() {
        let database = temp_database("api");
        let service = app(&database).unwrap();

        let preflight = service
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::OPTIONS)
                    .uri("/api/snippets")
                    .header(header::ORIGIN, "http://127.0.0.1:5173")
                    .header(header::ACCESS_CONTROL_REQUEST_METHOD, "POST")
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

        let create = service
            .clone()
            .oneshot(
                Request::post("/api/snippets")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"content":"hello UnionID"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(create.status(), StatusCode::CREATED);
        assert_eq!(create.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN], "*");

        let list = service
            .oneshot(Request::get("/api/snippets").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(list.status(), StatusCode::OK);
        let body = to_bytes(list.into_body(), usize::MAX).await.unwrap();
        let snippets: Vec<Snippet> = serde_json::from_slice(&body).unwrap();
        assert_eq!(snippets.len(), 1);
        assert_eq!(snippets[0].content, "hello UnionID");

        drop(snippets);
        let reopened = app(&database).unwrap();
        let list = reopened
            .clone()
            .oneshot(Request::get("/api/snippets").body(Body::empty()).unwrap())
            .await
            .unwrap();
        let body = to_bytes(list.into_body(), usize::MAX).await.unwrap();
        let persisted: Vec<Snippet> = serde_json::from_slice(&body).unwrap();
        assert_eq!(persisted.len(), 1);

        let deleted = reopened
            .oneshot(
                Request::delete(format!("/api/snippets/{}", persisted[0].id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

        let _ = std::fs::remove_file(database);
    }
}
