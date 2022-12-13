use aptos_sdk::types::account_address::AccountAddress;

#[derive(Debug, Clone)]
pub struct User {
    pub address: AccountAddress,
}

impl User {
    pub fn new(address: AccountAddress) -> Self {
        User { address }
    }
}
