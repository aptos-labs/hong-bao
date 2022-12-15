use crate::error::{Error, Result};
use crate::proto::{InputParcel, OutputParcel};
use aptos_sdk::types::account_address::AccountAddress;
use futures::stream::SplitStream;
use futures::{future, Stream, TryStream, TryStreamExt};
use std::time::Duration;
use std::{error, result};
use tokio_stream::StreamExt;
use warp::filters::ws::WebSocket;

#[derive(Clone, Copy)]
pub struct Client {
    // The address of the account of the user.
    pub address: AccountAddress,
}

impl Client {
    pub fn new(address: AccountAddress) -> Self {
        Client { address }
    }

    pub fn read_input(
        &self,
        stream: SplitStream<WebSocket>,
    ) -> impl Stream<Item = Result<InputParcel>> {
        let client_address = self.address;
        stream
            // Take only text messages
            .take_while(|message| {
                if let Ok(message) = message {
                    message.is_text()
                } else {
                    false
                }
            })
            // Deserialize JSON messages into proto::Input
            .map(move |message| match message {
                Err(err) => Err(Error::System(format!("{:#}", err))),
                Ok(message) => {
                    let input = serde_json::from_str(message.to_str().unwrap())?;
                    Ok(InputParcel::new(client_address, input))
                }
            })
            .throttle(Duration::from_millis(300))
    }

    pub fn write_output<S, E>(&self, stream: S) -> impl Stream<Item = Result<warp::ws::Message>>
    where
        S: TryStream<Ok = OutputParcel, Error = E> + Stream<Item = result::Result<OutputParcel, E>>,
        E: error::Error,
    {
        let client_address = self.address;
        stream
            // Skip irrelevant parcels
            .try_filter(move |output_parcel| {
                future::ready(output_parcel.client_address == client_address)
            })
            // Serialize to JSON
            .map_ok(|output_parcel| {
                let data = serde_json::to_string(&output_parcel.output).unwrap();
                warp::ws::Message::text(data)
            })
            .map_err(|err| Error::System(err.to_string()))
    }
}
