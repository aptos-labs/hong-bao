module addr::keyless {
    use std::error;
    use std::vector;
    use aptos_std::hash;
    use aptos_framework::account;

    /// You must use an Aptos Keyless account.
    const E_INVALID_PUBLIC_KEY: u64 = 200;

    /// Assert that a given account is a single key, non-federated, keyless account.
    public fun assert_is_keyless(
        account_address: address, public_key_bytes: vector<u8>
    ) {
        let expected_authentication_key_bytes =
            account::get_authentication_key(account_address);

        let pre_hash: vector<u8> = vector::empty();
        pre_hash.push_back(3u8);
        pre_hash.append(public_key_bytes);
        pre_hash.push_back(2u8);
        let derived_authentication_key_bytes = hash::sha3_256(pre_hash);

        assert!(
            expected_authentication_key_bytes == derived_authentication_key_bytes,
            error::invalid_argument(E_INVALID_PUBLIC_KEY)
        );
    }
}
