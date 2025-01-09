module addr::paylink {
    use std::vector;
    use std::error;
    use aptos_framework::ed25519;

    /// This is for paylink verification key validation.
    const ED25519_PUBLIC_KEY_LENGTH: u64 = 32;

    /// You provided a verification key that is not the correct length.
    const E_INVALID_LENGTH_VERIFICATION_KEY: u64 = 100;

    /// Your message was not signed with the correct private key or has the incorrect format.
    const E_INVALID_SIGNATURE: u64 = 101;

    /// This is the message that the client signs and passes in as signed_message.
    struct ClaimMessage has drop {
        gift_address: address,
        snatcher_address: address
    }

    /// When a creator makes a gift, use this to validate the verification key.
    public fun assert_valid_paylink_verification_key(
        verification_key: &vector<u8>
    ) {
        assert!(
            vector::length(verification_key) == ED25519_PUBLIC_KEY_LENGTH,
            error::invalid_argument(E_INVALID_LENGTH_VERIFICATION_KEY)
        );
    }

    /// When a snatcher claims a gift, they provide a signed message to provide that
    /// they came from the paylink (which contains the private key corresponding to
    /// the public key (the verification key). Use this function to validate that the
    /// signed message indeed corresponds to the paylink.
    public fun assert_signed_message_is_valid(
        gift_address: address,
        snatcher_address: address,
        // This should correspond to `paylink_verification_key` in `Gift`.
        verification_key: vector<u8>,
        // This is the signed message that the snatcher provides.
        signed_message_bytes: vector<u8>
    ) {
        let message = ClaimMessage { gift_address, snatcher_address };
        let unvalidated_pk =
            ed25519::new_unvalidated_public_key_from_bytes(verification_key);
        let signature = ed25519::new_signature_from_bytes(signed_message_bytes);
        let is_valid =
            ed25519::signature_verify_strict_t(&signature, &unvalidated_pk, message);
        assert!(is_valid, E_INVALID_SIGNATURE);
    }

    #[test_only]
    public fun build_claim_message(
        gift_address: address, snatcher_address: address
    ): ClaimMessage {
        ClaimMessage { gift_address, snatcher_address }
    }
}
