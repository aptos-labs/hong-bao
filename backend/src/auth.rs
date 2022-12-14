use crate::{
    api::{ApiErrors, JoinChatRoomRequest},
    indexer::IndexerClient,
};
use aptos_sdk::{
    crypto::{ed25519::Ed25519PublicKey, ValidCryptoMaterialStringExt},
    rest_client::Client as ApiClient,
    types::transaction::authenticator::AuthenticationKey,
};
use aptos_sdk::{
    crypto::{ed25519::Ed25519Signature, Signature},
    types::account_address::AccountAddress,
};
use std::{convert::TryFrom, sync::Arc};
use warp::Filter;

// This function ensures two things:
// 1. That the user submitting the request to join the chat room actually owns that account.
// 2. That the user has a token on their account that lets them join that chat room.
pub async fn ensure_authentication(
    _aptos_api_client: Arc<ApiClient>,
    indexer_client: Arc<IndexerClient>,
) -> impl Filter<Extract = (AccountAddress,), Error = warp::reject::Rejection> + Clone {
    // Annoyingly I have to compose the same filters I did in server.rs here to
    // give the middleware closure access to the clients.
    warp::body::json().and(warp::any().map(move || indexer_client.clone())).and_then(|join_chat_room_request: JoinChatRoomRequest, indexer_client: Arc<IndexerClient>| async move {
        // Build crypto representations of the public key and account address based on the request.
        let public_key = Ed25519PublicKey::from_encoded_string(&join_chat_room_request.chat_room_joiner)
            .map_err(|err| warp::reject::custom(ApiErrors::BadRequest(err.into())))?;
        let account_address = AuthenticationKey::ed25519(&public_key).derived_address();

        // Confirm that the user actually owns the account they are trying to join as.
        // On the client side, the user signed an arbitrary message with their private
        // key, resulting in the signature we check below. The verify function here
        // asserts that the signature was created with the private key corresponding to
        // the public key included in the request. If it doesn't, we reject the user.
        let signature_bytes = hex::decode(join_chat_room_request.signature)
            .map_err(|err| warp::reject::custom(ApiErrors::BadRequest(err.into())))?;
        let signature = Ed25519Signature::try_from(signature_bytes.as_slice())
            .map_err(|err| warp::reject::custom(ApiErrors::BadRequest(err.into())))?;
        signature.verify_arbitrary_msg(
            join_chat_room_request.message.as_bytes(),
            &public_key
        )
        .map_err(|err| warp::reject::custom(ApiErrors::BadRequest(err.into())))?;

        // Confirm that the user has a token on their account that lets them join the chat room.
        let tokens_owned_by_account = indexer_client.get_tokens_on_account(&account_address).await
            .map_err(|err| warp::reject::custom(ApiErrors::BadRequest(err.into())))?;
        let mut account_has_token = false;
        for collection in tokens_owned_by_account.current_token_ownerships.into_iter() {
            if collection.creator_address == join_chat_room_request.chat_room_creator.to_hex_literal() && collection.collection_name == join_chat_room_request.chat_room_name {
                account_has_token = true;
            }
        }

        if !account_has_token {
            return Err(warp::reject::custom(ApiErrors::DoesNotHoldChatRoomToken(
                "Account does not have a token that lets them access this chat room".to_string(),
            )));
        }

        Ok(account_address)
    })
}
