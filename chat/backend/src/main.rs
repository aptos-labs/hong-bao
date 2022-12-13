use clap::Parser;
use rusty_chat::server::Server;
use aptos_logger::info;

#[derive(Clone, Debug, Parser)]
pub struct ServerArgs {
    /// The address to listen on.
    #[clap(long, default_value = "0.0.0.0")]
    listen_address: String,

    /// The port to listen on.
    #[clap(long, default_value_t = 8888)] // Lucky number.
    listen_port: u16,
}

#[derive(Clone, Debug, Parser)]
pub struct Args {
    #[clap(flatten)]
    server_args: ServerArgs,
}

#[tokio::main]
async fn main() {
    aptos_logger::Logger::builder()
        .level(aptos_logger::Level::Info)
        .build();

    let args = Args::parse();
    info!("Running with args: {:#?}", args);

    let server = Server::new(
        args.server_args.listen_address.clone(),
        args.server_args.listen_port,
    );
    server.run().await;
}
