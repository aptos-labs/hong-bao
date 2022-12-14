use crate::model::feed::Feed;
use crate::model::message::Message;
use crate::model::user::User;
use crate::proto::{
    Input, InputParcel, JoinInput, JoinedOutput, MessageOutput, Output, OutputError, OutputParcel,
    PostInput, PostedOutput, UserJoinedOutput, UserLeftOutput, UserOutput, UserPostedOutput,
};
use aptos_sdk::types::account_address::AccountAddress;
use chrono::Utc;
use futures::StreamExt;
use std::collections::HashMap;
use std::time::Duration;
use tokio::sync::mpsc::UnboundedReceiver;
use tokio::sync::{broadcast, RwLock};
use tokio::time;
use tokio_stream::wrappers::UnboundedReceiverStream;
use uuid::Uuid;

const OUTPUT_CHANNEL_SIZE: usize = 16;
const MAX_MESSAGE_BODY_LENGTH: usize = 256;

#[derive(Clone, Copy, Default)]
pub struct HubOptions {
    pub alive_interval: Option<Duration>,
}

// A Hub is a single chat room.
pub struct Hub {
    alive_interval: Option<Duration>,
    output_sender: broadcast::Sender<OutputParcel>,
    users: RwLock<HashMap<AccountAddress, User>>,
    feed: RwLock<Feed>,
}

impl Hub {
    pub fn new(options: HubOptions) -> Self {
        let (output_sender, _) = broadcast::channel(OUTPUT_CHANNEL_SIZE);
        Hub {
            alive_interval: options.alive_interval,
            output_sender,
            users: Default::default(),
            feed: Default::default(),
        }
    }

    pub async fn run(&self, receiver: UnboundedReceiver<InputParcel>) {
        let ticking_alive = self.tick_alive();
        let receiver = UnboundedReceiverStream::new(receiver);
        let processing = receiver.for_each(|input_parcel| self.process(input_parcel));
        tokio::select! {
            _ = ticking_alive => {},
            _ = processing => {},
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<OutputParcel> {
        self.output_sender.subscribe()
    }

    pub async fn on_disconnect(&self, client_address: AccountAddress) {
        // Remove user on disconnect
        if self.users.write().await.remove(&client_address).is_some() {
            self.send_ignored(
                client_address,
                Output::UserLeft(UserLeftOutput::new(client_address)),
            )
            .await;
        }
    }

    async fn process(&self, input_parcel: InputParcel) {
        match input_parcel.input {
            Input::Join(input) => self.process_join(input_parcel.client_address, input).await,
            Input::Post(input) => self.process_post(input_parcel.client_address, input).await,
        }
    }

    async fn process_join(&self, client_address: AccountAddress, _input: JoinInput) {
        let user = User::new(client_address);
        self.users
            .write()
            .await
            .insert(client_address, user.clone());

        // Report success to user
        let user_output = UserOutput::new(client_address);
        let other_users = self
            .users
            .read()
            .await
            .values()
            .filter_map(|user| {
                if user.address != client_address {
                    Some(UserOutput::new(user.address))
                } else {
                    None
                }
            })
            .collect();
        let messages = self
            .feed
            .read()
            .await
            .messages_iter()
            .map(|message| {
                MessageOutput::new(
                    message.id,
                    UserOutput::new(message.user.address),
                    &message.body,
                    message.created_at,
                )
            })
            .collect();
        self.send_targeted(
            client_address,
            Output::Joined(JoinedOutput::new(
                user_output.clone(),
                other_users,
                messages,
            )),
        );

        // Notify others that someone joined
        self.send_ignored(
            client_address,
            Output::UserJoined(UserJoinedOutput::new(user_output)),
        )
        .await;
    }

    async fn process_post(&self, client_address: AccountAddress, input: PostInput) {
        // Verify that user exists
        let user = if let Some(user) = self.users.read().await.get(&client_address) {
            user.clone()
        } else {
            self.send_error(client_address, OutputError::NotJoined);
            return;
        };

        // Validate message body
        if input.body.is_empty() || input.body.len() > MAX_MESSAGE_BODY_LENGTH {
            self.send_error(client_address, OutputError::InvalidMessageBody);
            return;
        }

        let message = Message::new(Uuid::new_v4(), user.clone(), &input.body, Utc::now());
        self.feed.write().await.add_message(message.clone());

        let message_output = MessageOutput::new(
            message.id,
            UserOutput::new(user.address),
            &message.body,
            message.created_at,
        );
        // Report post status
        self.send_targeted(
            client_address,
            Output::Posted(PostedOutput::new(message_output.clone())),
        );
        // Notify everybody about new message
        self.send_ignored(
            client_address,
            Output::UserPosted(UserPostedOutput::new(message_output)),
        )
        .await;
    }

    async fn tick_alive(&self) {
        let alive_interval = if let Some(alive_interval) = self.alive_interval {
            alive_interval
        } else {
            return;
        };
        loop {
            time::sleep(alive_interval).await;
            self.send(Output::Alive).await;
        }
    }

    async fn send(&self, output: Output) {
        if self.output_sender.receiver_count() == 0 {
            return;
        }
        self.users.read().await.keys().for_each(|user_id| {
            self.output_sender
                .send(OutputParcel::new(*user_id, output.clone()))
                .unwrap();
        });
    }

    fn send_targeted(&self, client_address: AccountAddress, output: Output) {
        if self.output_sender.receiver_count() > 0 {
            self.output_sender
                .send(OutputParcel::new(client_address, output))
                .unwrap();
        }
    }

    async fn send_ignored(&self, ignored_client_address: AccountAddress, output: Output) {
        if self.output_sender.receiver_count() == 0 {
            return;
        }
        self.users
            .read()
            .await
            .values()
            .filter(|user| user.address != ignored_client_address)
            .for_each(|user| {
                self.output_sender
                    .send(OutputParcel::new(user.address, output.clone()))
                    .unwrap();
            });
    }

    fn send_error(&self, client_address: AccountAddress, error: OutputError) {
        self.send_targeted(client_address, Output::Error(error));
    }
}

impl Default for Hub {
    fn default() -> Self {
        Self::new(HubOptions::default())
    }
}

#[cfg(test)]
mod tests {
    use aptos_sdk::types::account_address::AccountAddress;
    use tokio::runtime::Runtime;
    use tokio::sync::mpsc;

    use crate::hub::{Hub, HubOptions};
    use crate::proto::{Input, InputParcel, JoinInput, Output, PostInput};

    #[test]
    fn join_and_post() {
        let hub = Hub::new(HubOptions::default());
        let (sender, receiver) = mpsc::unbounded_channel();
        let mut subscription = hub.subscribe();

        let rt = Runtime::new().unwrap();
        rt.block_on(async move {
            let case = async {
                let client_address = AccountAddress::ZERO;

                // Join
                sender
                    .send(InputParcel::new(
                        client_address,
                        Input::Join(JoinInput {
                            address: client_address,
                        }),
                    ))
                    .unwrap();
                let output = subscription.recv().await.unwrap().output;
                let user;
                if let Output::Joined(joined) = output {
                    user = joined.user;
                } else {
                    panic!("Expected Output::Joined got {:?}", output);
                }

                // Post message
                sender
                    .send(InputParcel::new(
                        client_address,
                        Input::Post(PostInput {
                            body: String::from("Hello"),
                        }),
                    ))
                    .unwrap();
                let output = subscription.recv().await.unwrap().output;
                if let Output::Posted(posted) = output {
                    assert_eq!(posted.message.body, "Hello");
                    assert_eq!(posted.message.user.address, user.address);
                } else {
                    panic!("Expected Output::Posted got {:?}", output);
                }

                return;
            };
            tokio::select! {
              _ = hub.run(receiver) => {},
              _ = case => {},
            }
        });
    }
}
