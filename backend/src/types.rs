use aptos_sdk::types::account_address::AccountAddress;

// A hub ID is really just the unique ID referring to a token collection, which is just
// the creator address + the collection name.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct HubId {
    // Account that created the collection.
    creator_address: AccountAddress,

    // Name of the collection.
    collection_name: String,
}

impl HubId {
    pub fn new(creator_address: AccountAddress, collection_name: String) -> Self {
        HubId {
            creator_address,
            collection_name,
        }
    }
}
