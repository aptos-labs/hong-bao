use crate::client::Client;
use crate::hub::{Hub, HubOptions};
use crate::proto::InputParcel;
use crate::types::HubId;
use aptos_logger::{error, info};
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
}

impl Server {
    pub fn new(listen_address: String, listen_port: u16) -> Self {
        Server {
            listen_address,
            listen_port,
            hubs: Arc::new(RwLock::new(HashMap::new())),
            /*
            hub: Arc::new(Hash::new(HubOptions {
                alive_interval: Some(Duration::from_secs(5)),
            })),
            */
        }
    }

    pub async fn run(&self) {
        let hubs = self.hubs.clone();

        let chat = warp::path!("chat" / AccountAddress / String)
            .and(warp::ws())
            .and(warp::any().map(move || hubs.clone()))
            .map(
                move |chat_room_creator: AccountAddress,
                      collection_name: String,
                      ws: warp::ws::Ws,
                      hubs: Arc<RwLock<HashMap<HubId, Arc<Hub>>>>| {
                    let hub_id = HubId::new(chat_room_creator, collection_name);
                    ws.max_frame_size(MAX_FRAME_SIZE)
                        .on_upgrade(move |web_socket| async move {
                            tokio::spawn(Self::process_client(hubs, hub_id, web_socket));
                        })
                },
            );

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
        hub_id: HubId,
        web_socket: WebSocket,
    ) {
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
