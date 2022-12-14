use crate::api::{handle_rejection, JoinChatRoomRequest};
use crate::args::RootArgs;
use crate::auth::ensure_authentication;
use crate::client::Client;
use crate::hub::{Hub, HubOptions};
use crate::indexer::IndexerClient;
use crate::proto::InputParcel;
use crate::types::HubId;
use aptos_logger::{error, info};
use aptos_sdk::rest_client::Client as ApiClient;
use aptos_sdk::types::account_address::AccountAddress;
use futures::{StreamExt, TryStreamExt};
use std::collections::HashMap;
use std::net::IpAddr;
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, RwLock};
use tokio_stream::wrappers::BroadcastStream;
use tokio_stream::wrappers::UnboundedReceiverStream;
use warp::ws::WebSocket;
use warp::Filter;

const MAX_FRAME_SIZE: usize = 65536;

pub struct Server {
    listen_address: String,
    listen_port: u16,

    // Map of HubId to Hub (aka chat room).
    hubs: Arc<RwLock<HashMap<HubId, Arc<Hub>>>>,

    // Client for connecting to an Aptos fullnode.
    api_client: Arc<ApiClient>,

    // Client for connecting to an Aptos indexer
    indexer_client: Arc<IndexerClient>,
}

impl Server {
    pub fn new(args: RootArgs) -> Self {
        Server {
            listen_address: args.server_args.listen_address,
            listen_port: args.server_args.listen_port,
            hubs: Arc::new(RwLock::new(HashMap::new())),
            api_client: Arc::new(ApiClient::new(args.fullnode_args.fullnode_url.clone())),
            indexer_client: Arc::new(IndexerClient::new(args.fullnode_args.fullnode_url.clone())),
        }
    }

    pub async fn run(&self) {
        let hubs = self.hubs.clone();
        let api_client = self.api_client.clone();
        let indexer_client = self.indexer_client.clone();

        let chat = warp::path!("chat")
            .and(warp::post())
            .and(warp::body::json())
            .and(ensure_authentication(api_client.clone(), indexer_client.clone()).await)
            .and(warp::ws())
            .and(warp::any().map(move || hubs.clone()))
            .map(
                move |request: JoinChatRoomRequest,
                      account_address: AccountAddress,
                      ws: warp::ws::Ws,
                      hubs: Arc<RwLock<HashMap<HubId, Arc<Hub>>>>| {
                    ws.max_frame_size(MAX_FRAME_SIZE)
                        .on_upgrade(move |web_socket| async move {
                            tokio::spawn(Self::process_client(
                                hubs,
                                request,
                                account_address,
                                web_socket,
                            ));
                        })
                },
            )
            .recover(handle_rejection);

        let shutdown = async {
            tokio::signal::ctrl_c()
                .await
                .expect("Failed to install CTRL+C signal handler");
        };
        let (addr, serving) = warp::serve(chat).bind_with_graceful_shutdown(
            (
                IpAddr::from_str(&self.listen_address).expect("Listen address was invalid"),
                self.listen_port,
            ),
            shutdown,
        );

        info!("Running on {}", addr);

        serving.await
    }

    async fn process_client(
        hubs: Arc<RwLock<HashMap<HubId, Arc<Hub>>>>,
        request: JoinChatRoomRequest,
        _joiner_account_address: AccountAddress,
        web_socket: WebSocket,
    ) {
        let hub_id = HubId::new(request.chat_room_creator, request.chat_room_name);

        // At this point we have verified that the requester is truly the owner of the
        // account that they say they are. Now we need to check if a Hub already exists
        // for the chat they're trying to join. If not, we'll create one.
        let hub = {
            let mut hubs = hubs.write().await;
            if let Some(hub) = hubs.get(&hub_id) {
                hub.clone()
            } else {
                let hub = Arc::new(Hub::new(HubOptions {
                    alive_interval: Some(Duration::from_secs(5)),
                }));
                hubs.insert(hub_id.clone(), hub.clone());
                hub
            }
        };

        let (input_sender, input_receiver) = mpsc::unbounded_channel::<InputParcel>();

        let output_receiver = hub.subscribe();
        let output_receiver = BroadcastStream::new(output_receiver);
        let (ws_sink, ws_stream) = web_socket.split();
        // TODO Use address from request.
        let client = Client::new(AccountAddress::ZERO);

        info!(address = client.address, event = "connected");

        let reading = client
            .read_input(ws_stream)
            .try_for_each(|input_parcel| async {
                input_sender.send(input_parcel).unwrap();
                Ok(())
            });

        let (tx, rx) = mpsc::unbounded_channel();
        let rx = UnboundedReceiverStream::new(rx);
        tokio::spawn(rx.forward(ws_sink));
        let writing = client
            .write_output(output_receiver)
            .try_for_each(|message| async {
                tx.send(Ok(message)).unwrap();
                Ok(())
            });

        let running_hub = hub.run(input_receiver);

        if let Err(err) = tokio::select! {
            result = reading => result,
            result = writing => result,
            _ = running_hub => Ok(()),
        } {
            error!("Client connection error: {}", err);
        }

        hub.on_disconnect(client.address).await;
        info!(address = client.address, event = "disconnected");
    }
}
