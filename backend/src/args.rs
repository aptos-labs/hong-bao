use clap::Parser;
use reqwest::Url;

#[derive(Clone, Debug, Parser)]
pub struct ServerArgs {
    /// The address to listen on.
    #[clap(long, default_value = "0.0.0.0")]
    pub listen_address: String,

    /// The port to listen on.
    #[clap(long, default_value_t = 8888)] // Lucky number.
    pub listen_port: u16,
}

#[derive(Clone, Debug, Parser)]
pub struct FullnodeArgs {
    #[clap(long, default_value = "https://fullnode.testnet.aptoslabs.com")]
    pub fullnode_url: Url,
}

#[derive(Clone, Debug, Parser)]
pub struct IndexerArgs {
    #[clap(
        long,
        default_value = "https://indexer-testnet.staging.gcp.aptosdev.com/v1/graphql"
    )]
    pub indexer_url: Url,
}

#[derive(Clone, Debug, Parser)]
pub struct RootArgs {
    #[clap(flatten)]
    pub server_args: ServerArgs,

    #[clap(flatten)]
    pub fullnode_args: FullnodeArgs,

    #[clap(flatten)]
    pub indexer_args: IndexerArgs,
}
