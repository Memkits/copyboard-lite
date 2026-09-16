use std::net::SocketAddr;
use std::path::PathBuf;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let address: SocketAddr = std::env::var("COPYBOARD_ADDR")
        .unwrap_or_else(|_| "127.0.0.1:11030".into())
        .parse()?;
    let database = std::env::var_os("COPYBOARD_DB")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("data/copyboard.redb"));
    if let Some(parent) = database.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let listener = tokio::net::TcpListener::bind(address).await?;
    println!("copyboard-lite API listening on http://{address}");
    axum::serve(listener, copyboard_lite::app(database)?).await?;
    Ok(())
}
