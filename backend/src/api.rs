use aptos_logger::error;
use aptos_sdk::types::account_address::AccountAddress;
use serde::{Deserialize, Serialize};
use std::convert::Infallible;
use thiserror::Error;
use warp::hyper::StatusCode;

#[derive(Debug, Deserialize, Serialize)]
pub struct JoinChatRoomRequest {
    /// The account address of the creator of the chat room.
    pub chat_room_creator: AccountAddress,

    /// The name of the chat room. This is unique based on the creator of the chat
    /// room. Under the hood this is the collection name.
    pub chat_room_name: String,

    /// The public key of the person requesting to join the chat room.
    /// This should be a hex string representation of an account ed25519 public key.
    pub chat_room_joiner: String,

    /// The payload that the web UI had the wallet sign to prove that the person
    /// making the request to join the room actually owns the account corresponding
    /// to the given public key. When you call window.aptos.signMessage the response
    /// contains a field called `signature`. This is a hex encoded representation of
    /// the signed message. That is what this field should be.
    pub signature: String,

    /// This is similar to the previous field but instead of signature, it's the fullMessage.
    pub full_message: String,
}

#[derive(Error, Debug)]
pub enum ApiError {
    #[error("User is could submitted an invalid join request: {0:#}")]
    BadRequest(#[from] anyhow::Error),

    #[error("User is could not prove they owned the account in the request: {0}")]
    NotRealAccountOwner(String),

    #[error("User is not authorized to join this chat room: {0}")]
    DoesNotHoldChatRoomToken(String),
}

impl warp::reject::Reject for ApiError {}

#[derive(Serialize, Debug)]
struct ApiErrorResult {
    message: String,
}

pub async fn handle_rejection(
    err: warp::reject::Rejection,
) -> std::result::Result<impl warp::reply::Reply, Infallible> {
    let code;
    let message: String;

    if err.is_not_found() {
        code = StatusCode::NOT_FOUND;
        message = "Not found".to_string();
    } else if let Some(_) = err.find::<warp::filters::body::BodyDeserializeError>() {
        code = StatusCode::BAD_REQUEST;
        message = "Invalid Body".to_string();
    } else if let Some(err) = err.find::<ApiError>() {
        match err {
            ApiError::BadRequest(error_message) => {
                code = StatusCode::BAD_REQUEST;
                message = format!("{:#}", error_message);
            }
            ApiError::NotRealAccountOwner(error_message) => {
                code = StatusCode::UNAUTHORIZED;
                message = error_message.to_string();
            }
            ApiError::DoesNotHoldChatRoomToken(error_message) => {
                code = StatusCode::UNAUTHORIZED;
                message = error_message.to_string();
            }
        }
    } else if let Some(_) = err.find::<warp::reject::MethodNotAllowed>() {
        code = StatusCode::METHOD_NOT_ALLOWED;
        message = "Method not allowed".to_string();
    } else {
        // We should have expected this... Just log and say its a 500
        error!("Unhandled rejection: {:?}", err);
        code = StatusCode::INTERNAL_SERVER_ERROR;
        message = "Internal server error".to_string();
    }

    let json = warp::reply::json(&ApiErrorResult {
        message: message.into(),
    });

    Ok(warp::reply::with_status(json, code))
}
