use aptos_hong_bao_backend::{args::RootArgs, server::Server};
use aptos_logger::info;
use clap::Parser;

#[tokio::main]
async fn main() {
    aptos_logger::Logger::builder()
        .level(aptos_logger::Level::Info)
        .build();

    let args = RootArgs::parse();
    info!("Running with args: {:#?}", args);

    let server = Server::new(args);
    server.run().await;
}
