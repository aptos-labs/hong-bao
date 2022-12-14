use aptos_logger::error;
use serde::Serialize;
use std::convert::Infallible;
use thiserror::Error;
use warp::hyper::StatusCode;

#[derive(Error, Debug)]
pub enum ApiErrors {
    #[error("User is could not prove they owned the account in the request: {0}")]
    NotRealAccountOwner(String),

    #[error("User is not authorized to join this chat room: {0}")]
    DoesNotHoldChatRoomToken(String),
}

impl warp::reject::Reject for ApiErrors {}

#[derive(Serialize, Debug)]
struct ApiErrorResult {
    message: String,
}

pub async fn handle_rejection(
    err: warp::reject::Rejection,
) -> std::result::Result<impl warp::reply::Reply, Infallible> {
    let code;
    let message;

    if err.is_not_found() {
        code = StatusCode::NOT_FOUND;
        message = "Not found";
    } else if let Some(_) = err.find::<warp::filters::body::BodyDeserializeError>() {
        code = StatusCode::BAD_REQUEST;
        message = "Invalid Body";
    } else if let Some(e) = err.find::<ApiErrors>() {
        match e {
            ApiErrors::NotRealAccountOwner(error_message) => {
                code = StatusCode::UNAUTHORIZED;
                message = error_message;
            }
            ApiErrors::DoesNotHoldChatRoomToken(error_message) => {
                code = StatusCode::UNAUTHORIZED;
                message = error_message;
            }
        }
    } else if let Some(_) = err.find::<warp::reject::MethodNotAllowed>() {
        code = StatusCode::METHOD_NOT_ALLOWED;
        message = "Method not allowed";
    } else {
        // We should have expected this... Just log and say its a 500
        error!("Unhandled rejection: {:?}", err);
        code = StatusCode::INTERNAL_SERVER_ERROR;
        message = "Internal server error";
    }

    let json = warp::reply::json(&ApiErrorResult {
        message: message.into(),
    });

    Ok(warp::reply::with_status(json, code))
}
