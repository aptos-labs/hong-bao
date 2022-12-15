// If ever updating this version, also update:
// - frontend/src/move/constants.ts
module addr::hongbao02 {
    use std::string;
    use std::error;
    use std::signer;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};

    /// The snatcher tried to snatch a packet from a Gift on an account that
    /// doesn't have a GiftHolder.
    const E_NOT_INITIALIZED: u64 = 1;

    /// The creator tried to create a gift with an expiration time in the past.
    const E_GIFT_EXPIRED_IN_PAST: u64 = 2;

    /// The creator tried to create a Gift with a key that is already used.
    const E_GIFT_ALREADY_EXISTS_WITH_THIS_KEY: u64 = 3;

    /// The snatcher tried to snatch a packet from a Gift that has expired.
    const E_GIFT_EXPIRED: u64 = 4;

    // The snatcher tried to snatch a packet from their own Gift.
    const E_SNATCHER_IS_GIFTER: u64 = 5;

    /// The snatcher tried to snatch a packet from a Gift, but they're not in the
    /// allowed recipients list.
    const E_NOT_ALLOWED_TO_SNATCH: u64 = 6;

    /// The snatcher tried to snatch a packet from a Gift, but there are no more
    /// packets left.
    const E_NO_PACKETS_LEFT: u64 = 7;

    /// The creator tried to reclaim a Gift that hasn't expired yet.
    const E_GIFT_NOT_EXPIRED_YET: u64 = 8;

    #[test_only]
    /// Used for assertions in tests.
    const E_TEST_FAILURE: u64 = 100;

    /// If a user wants to create a Gift, they must first initialize one of these to
    /// their account. This tracks all the Gifts they have created.
    struct GiftHolder has key, store {
        /// The Gifts the user has created. This is keyed by the chat room ID, which
        /// is really just this string: "${collectionCreatorAddress}:{collectionName}".
        /// To explain, each chat room is tied to an NFT collection. NFT collections can
        /// be uniquely identified by the creator (address) + the collection name.
        /// This means that one person can only have one active Gift sent out per chat
        /// at any given time.
        gifts: simple_map::SimpleMap<string::String, Gift>,
    }

    /// This contains all the information relevant to a single Gift. A single Gift is
    /// disbursed as many packets, matching how it works irl / in other apps.
    struct Gift has key, store {
        /// This contains the addresses of all the people who are allowed to snatch
        /// a packet from this Gift. This is a map of address -> bool because what we
        /// really want here is a set, but that doesn't exist right now. When someone
        /// snatches a packet, we remove them from this map.
        allowed_recipients: simple_map::SimpleMap<address, bool>,

        /// The total number of packets (aka how many chunks we break the Gift into) left
        /// in this Gift.
        remaining_packets: u64,

        /// The total amount of APT remaining in this Gift.
        remaining_balance: Coin<AptosCoin>,

        /// When the Gift expires. At this point, no one can snatch any more packets
        /// and the creator can call the `reclaim` function. Unixtime in seconds.
        expiration_time: u64,
    }

    /// For now we accept gift_key as a single string instead of as creator_address plus
    /// collection name for the sake of simplicity.
    public entry fun create_gift(
        account: &signer,
        gift_key: string::String,
        allowed_recipients: vector<address>,
        // The number of "chunks" we'll break the Gift into.
        num_packets: u64,
        // Gift amount in OCTA.
        gift_amount: u64,
        // When the Gift expires.
        expiration_time: u64,
    ) acquires GiftHolder {
        let addr = signer::address_of(account);

        // Make sure the expiration time is in the future.
        assert!(expiration_time > timestamp::now_seconds(), error::invalid_state(E_GIFT_EXPIRED_IN_PAST));

        // Create a GiftHolder if necessary.
        if (!exists<GiftHolder>(addr)) {
            move_to(account, GiftHolder {
                gifts: simple_map::create(),
            });
        };

        // Ensure a Gift doesn't already exist with this gift key.
        let gift_holder = borrow_global_mut<GiftHolder>(addr);
        assert!(!simple_map::contains_key(&gift_holder.gifts, &gift_key), error::invalid_state(E_GIFT_ALREADY_EXISTS_WITH_THIS_KEY));

        // Take the coins from the user.
        let coins = coin::withdraw<AptosCoin>(account, gift_amount);

        // Create the set of allowed recipients.
        let allowed_recipients_map = simple_map::create();
        while (vector::length(&allowed_recipients) > 0) {
            let recipient = vector::pop_back(&mut allowed_recipients);
            // Make sure the creator is not putting themself in `allowed_recipients`.
            assert!(recipient != addr, error::invalid_state(E_SNATCHER_IS_GIFTER));
            simple_map::add(&mut allowed_recipients_map, recipient, true);
        };

        // Create the Gift.
        let gift = Gift {
            allowed_recipients: allowed_recipients_map,
            remaining_packets: num_packets,
            remaining_balance: coins,
            expiration_time: expiration_time,
        };

        simple_map::add(&mut gift_holder.gifts, gift_key, gift);
    }

    /// People can call this function to try and snatch a packet from the Gift.
    /// If they're not in the allowed recipients list they will be rejected.
    /// If there are no more packets left, they will also be rejected.
    /// For now, since we don't have randomness available, we just give each
    /// snatcher half of the total remaining balance, until we get down to one
    /// packet left, at which point we give the remaining balance to that caller.
    public entry fun snatch_packet(
        snatcher_account: &signer,
        // The address of the person who created the Gift.
        gifter_address: address,
        // The ID of the Gift on their account.
        gift_id: string::String,
    ) acquires GiftHolder {
        let snatcher_address = signer::address_of(snatcher_account);

        // Make sure the Gift exists.
        assert!(exists<GiftHolder>(gifter_address), error::invalid_state(E_NOT_INITIALIZED));

        // Get the Gift. This will result in an error if there is no gift with this ID.
        let gift_holder = borrow_global_mut<GiftHolder>(gifter_address);
        let gift = simple_map::borrow_mut(&mut gift_holder.gifts, &gift_id);

        // Make sure the snatcher is not the person who created the gift.
        assert!(snatcher_address != gifter_address, error::invalid_state(E_SNATCHER_IS_GIFTER));

        // Make sure the Gift hasn't expired.
        assert!(
            timestamp::now_seconds() < gift.expiration_time,
            error::invalid_state(E_GIFT_EXPIRED)
        );

        // Make sure the snatcher is allowed to snatch a packet / hasn't already snatched one.
        assert!(simple_map::contains_key(&gift.allowed_recipients, &snatcher_address), error::invalid_state(E_NOT_ALLOWED_TO_SNATCH));

        // Make sure there are still packets left.
        assert!(gift.remaining_packets > 0, error::invalid_state(E_NO_PACKETS_LEFT));

        // Okay, the user is allowed to snatch a packet! Transfer half of the remaining
        // balance to them.
        let amount_to_withdraw = coin::value(&gift.remaining_balance) / 2;
        let coins = coin::extract<AptosCoin>(&mut gift.remaining_balance, amount_to_withdraw);
        coin::deposit<AptosCoin>(snatcher_address, coins);

        // Mark the snatcher as having snatched a packet.
        simple_map::remove(&mut gift.allowed_recipients, &snatcher_address);
    }

    public entry fun reclaim_gift(
        account: &signer,
        // The ID of the Gift on their account.
        gift_id: string::String,
    ) acquires GiftHolder {
        let addr = signer::address_of(account);

        // Make sure the GiftHolder exists.
        assert!(exists<GiftHolder>(addr), error::invalid_state(E_NOT_INITIALIZED));

        // Get the Gift. This will result in an error if there is no gift with this ID.
        let gift_holder = borrow_global_mut<GiftHolder>(addr);
        let gift = simple_map::borrow_mut(&mut gift_holder.gifts, &gift_id);

        // Make sure the Gift has expired.
        assert!(
            timestamp::now_seconds() >= gift.expiration_time,
            error::invalid_state(E_GIFT_NOT_EXPIRED_YET)
        );

        // The creator is allowed to reclaim the Gift. Transfer the remaining balance
        // back to them.
        let coins = coin::extract_all<AptosCoin>(&mut gift.remaining_balance);
        coin::deposit<AptosCoin>(addr, coins);

        // Remove the Gift from the GiftHolder. We have to deconstruct a bit to
        // ultimately destroy the empty Coin safely.
        let (_key, gift) = simple_map::remove(&mut gift_holder.gifts, &gift_id);
        let Gift {
            allowed_recipients: _allowed_recipients,
            remaining_packets: _remaining_packets,
            remaining_balance,
            expiration_time: _expiration_time,
        } = gift;
        coin::destroy_zero(remaining_balance);
    }

    /*
    #[test(aptos_framework = @aptos_framework, account = @0x123)]
    public entry fun test_stuff(aptos_framework: &signer, account: signer) {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let addr = signer::address_of(&account);
    }
    */
}