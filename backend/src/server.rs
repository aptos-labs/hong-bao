use crate::api::{handle_rejection, JoinChatRoomRequest};
use crate::args::RootArgs;
use crate::auth::authenticate_user;
use crate::client::Client;
use crate::hub::{Hub, HubOptions};
use crate::indexer::IndexerClient;
use crate::proto::InputParcel;
use crate::types::HubId;
use anyhow::Context;
use aptos_logger::{error, info};
use aptos_sdk::rest_client::Client as ApiClient;
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
            indexer_client: Arc::new(IndexerClient::new(args.indexer_args.indexer_url.clone())),
        }
    }

    pub async fn run(&self) {
        let hubs = self.hubs.clone();
        let api_client = self.api_client.clone();
        let indexer_client = self.indexer_client.clone();

        let chat = warp::path!("chat")
            .and(warp::ws())
            .and(warp::any().map(move || api_client.clone()))
            .and(warp::any().map(move || indexer_client.clone()))
            .and(warp::any().map(move || hubs.clone()))
            .map(
                move |ws: warp::ws::Ws,
                      api_client: Arc<ApiClient>,
                      indexer_client: Arc<IndexerClient>,
                      hubs: Arc<RwLock<HashMap<HubId, Arc<Hub>>>>| {
                    ws.max_frame_size(MAX_FRAME_SIZE)
                        .on_upgrade(move |web_socket| async move {
                            tokio::spawn(Self::process_client(
                                hubs,
                                api_client,
                                indexer_client,
                                web_socket,
                            ));
                        })
                },
            );

        let health = warp::path::end()
            .map(|| "Healthy! Try connecting to a chat room at the /chat endpoint!");

        let routes = chat.or(health).recover(handle_rejection);

        let shutdown = async {
            tokio::signal::ctrl_c()
                .await
                .expect("Failed to install CTRL+C signal handler");
        };
        let (addr, serving) = warp::serve(routes).bind_with_graceful_shutdown(
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
        _api_client: Arc<ApiClient>,
        indexer_client: Arc<IndexerClient>,
        mut web_socket: WebSocket,
    ) {
        // Here we authenticate the user. It'd be more ideal to do this when the request // is first received, and therefore before we get to this point with an established,
        // websocket, but unfortunately it's not easy to do this when the request is first
        // received: https://websockets.readthedocs.io/en/stable/topics/authentication.html,
        // so instead we block here waiting for the first message, which must contain
        // the auth info, before proceeding.

        // Wait for the first message.
        let first_message = match web_socket.try_next().await {
            Ok(Some(message)) => message,
            Ok(None) => {
                error!(event = "disconnected_before_first_message");
                let _ = web_socket.close().await;
                return;
            }
            Err(e) => {
                error!(error = ?e, event="error_receiving_first_message");
                return;
            }
        };

        // Assert that we can deserialize the first message as a JoinChatRoomRequest.
        if !first_message.is_text() {
            error!(event = "first_message_not_text");
            let _ = web_socket.close().await;
            return;
        }
        let first_message = match first_message.to_str() {
            Ok(message) => message,
            Err(e) => {
                let _ = web_socket.close().await;
                error!(error = ?e, event="error_converting_first_message_to_str");
                return;
            }
        };
        let request: JoinChatRoomRequest = match serde_json::from_str(&first_message) {
            Ok(message) => message,
            Err(e) => {
                let _ = web_socket.close().await;
                error!(error = ?e, event="error_deserializing_first_message");
                return;
            }
        };

        // Finally, authenticate the request.
        let user_account_address = match authenticate_user(indexer_client.clone(), &request).await {
            Ok(address) => address,
            Err(e) => {
                let _ = web_socket.close().await;
                error!(error = ?e, event="user_forbidden");
                return;
            }
        };

        // TODO Use address from request.
        let client = Client::new(user_account_address);

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

        let (ws_sink, ws_stream) = web_socket.split();

        let (input_sender, input_receiver) = mpsc::unbounded_channel::<InputParcel>();

        let output_receiver = hub.subscribe();
        let output_receiver = BroadcastStream::new(output_receiver);

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
            result = reading => result.context("Error reading from websocket"),
            result = writing => result.context("Error writing to websocket"),
            _ = running_hub => Ok(()),
        } {
            error!("Client connection error: {:#}", err);
        }

        hub.on_disconnect(client.address).await;
        info!(address = client.address, event = "disconnected");
    }
}
