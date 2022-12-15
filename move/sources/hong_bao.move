// If ever updating this version, also update:
// - frontend/src/api/move/constants.ts
module addr::hongbao14 {
    use std::string::{Self, String};
    use std::error;
    use std::signer;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_token::token::{Self, TokenId};
    use aptos_token::token_transfers::{Self};

    /// The snatcher tried to snatch a packet from a Gift on an account that
    /// doesn't have a GiftHolder.
    const E_NOT_INITIALIZED: u64 = 1;

    /// The creator tried to create a gift with no allowed recipients.
    const E_NO_RECIPIENTS_SPECIFIED: u64 = 2;

    /// The creator tried to create a gift with an expiration time in the past.
    const E_GIFT_EXPIRED_IN_PAST: u64 = 3;

    /// The creator tried to create a Gift with a key that is already used.
    const E_GIFT_ALREADY_EXISTS_WITH_THIS_KEY: u64 = 4;

    /// The snatcher tried to snatch a packet from a Gift that has expired.
    const E_GIFT_EXPIRED: u64 = 5;

    // The snatcher tried to snatch a packet from their own Gift.
    const E_SNATCHER_IS_GIFTER: u64 = 6;

    /// The snatcher tried to snatch a packet from a Gift, but they're not in the
    /// allowed recipients list.
    const E_NOT_ALLOWED_TO_SNATCH: u64 = 7;

    /// The snatcher tried to snatch a packet from a Gift, but there are no more
    /// packets left.
    const E_NO_PACKETS_LEFT: u64 = 8;

    /// The creator tried to reclaim a Gift that hasn't expired yet.
    const E_GIFT_NOT_EXPIRED_YET: u64 = 9;

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

        // Make sure there is at least one allowed recipient.
        assert!(vector::length(&allowed_recipients) > 0, error::invalid_state(E_NOT_ALLOWED_TO_SNATCH));

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
        // balance to them, unless there is only one packet left, in which case we
        // transfer the rest.
        let amount_to_withdraw;
        if (gift.remaining_packets == 1) {
            amount_to_withdraw = coin::value(&gift.remaining_balance);
        } else {
            amount_to_withdraw = coin::value(&gift.remaining_balance) / 2;
        };
        let coins = coin::extract<AptosCoin>(&mut gift.remaining_balance, amount_to_withdraw);
        coin::deposit<AptosCoin>(snatcher_address, coins);

        // Mark the snatcher as having snatched a packet.
        simple_map::remove(&mut gift.allowed_recipients, &snatcher_address);

        gift.remaining_packets = gift.remaining_packets - 1;

        // If there are no packets left, remove the Gift from the map.
        if (gift.remaining_packets == 0) {
            delete_gift(&mut gift_holder.gifts, &gift_id);
        }
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
        delete_gift(&mut gift_holder.gifts, &gift_id);
    }

    /// If the last packet has been snatched, or the Gift has expired, remove it
    /// with this function.
    fun delete_gift(gifts: &mut simple_map::SimpleMap<string::String, Gift>, gift_id: &string::String) {
        let (_key, gift) = simple_map::remove(gifts, gift_id);
        let Gift {
            allowed_recipients: _allowed_recipients,
            remaining_packets: _remaining_packets,
            remaining_balance,
            expiration_time: _expiration_time,
        } = gift;
        coin::destroy_zero(remaining_balance);
    }

    /// Create a chat room and invite people to it. Concretely this means creating a new
    /// NFT collection, minting tokens for each person, and then offering them to them.
    public entry fun create_chat_room(creator: &signer, collection_name: String, addresses: vector<address>) {
        let description = string::utf8(b"My Awesome Chat Room");
        let collection_uri = string::utf8(b"Collection URI");
        // This means that the supply of the token will not be tracked.
        let maximum_supply = 0;
        // This variable sets if we want to allow mutation for collection description, uri, and maximum.
        // Here, we are setting all of them to false, which means that we don't allow mutations to any CollectionData fields.
        let mutate_setting = vector<bool>[ false, false, false ];

        // Create the nft collection.
        token::create_collection(creator, collection_name, description, collection_uri, maximum_supply, mutate_setting);

        // Mint a token for this account and immediately offer + claim it.
        let token_id = create_token(creator, collection_name, 0);
        token_transfers::offer(
            creator,
            signer::address_of(creator),
            token_id,
            1,
        );
        token_transfers::claim(creator, signer::address_of(creator), token_id);

        // Mint tokens and offer them to folks..
        let index = 1;
        loop {
            let token_id = create_token(creator, collection_name, index);
            let address = vector::pop_back(&mut addresses);
            token_transfers::offer(
                creator,
                address,
                token_id,
                1,
            );
            if (vector::length(&addresses) == 0) {
                break
            };
            index = index + 1;
        };

    }

    fun create_token(creator: &signer, collection_name: String, index: u64): TokenId {
        let token_name = collection_name;
        string::append(&mut token_name, string::utf8(b" member #"));
        string::append(&mut token_name, to_string(index));
        let token_uri = string::utf8(b"Token uri");
        let token_data_id = token::create_tokendata(
            creator,
            collection_name,
            token_name,
            string::utf8(b"description"),
            0,
            token_uri,
            signer::address_of(creator),
            1,
            0,
            // This variable sets if we want to allow mutation for token maximum, uri, royalty, description, and properties.
            // Here we enable mutation for properties by setting the last boolean in the vector to true.
            token::create_token_mutability_config(
                &vector<bool>[ false, false, false, false, true ]
            ),
            // We can use property maps to record attributes related to the token.
            // In this example, we are using it to record the receiver's address.
            // We will mutate this field to record the user's address
            // when a user successfully mints a token in the `mint_nft()` function.
            vector<String>[string::utf8(b"given_to")],
            vector<vector<u8>>[b""],
            vector<String>[ string::utf8(b"address") ],
        );
        token::mint_token(
            creator,
            token_data_id,
            1,
        )
    }

    /// Converts a `u64` to its `ascii::String` decimal representation.
    fun to_string(value: u64): String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }

    /*
    #[test(aptos_framework = @aptos_framework, account = @0x123)]
    public entry fun test_stuff(aptos_framework: &signer, account: signer) {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let addr = signer::address_of(&account);
    }
    */
}
