use aptos_sdk::types::account_address::AccountAddress;
use warp::Filter;

use crate::response::ApiErrors;

// This function ensures two things:
// 1. That the user submitting the request to join the chat room actually owns that account.
// 2. That the user has a token on their account that lets them join that chat room.
pub async fn ensure_authentication(
) -> impl Filter<Extract = (String,), Error = warp::reject::Rejection> + Clone {
    warp::path::param().and(warp::path::param()).and_then(
        |chat_room_creator: AccountAddress, collection_name: String| async move {
            Err(warp::reject::custom(ApiErrors::NotRealAccountOwner(
                "not authorized".to_string(),
            )))
        },
    )
}
