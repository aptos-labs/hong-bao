module addr::hongbao {
    use addr::keyless;
    use addr::paylink;
    use addr::dirichlet;
    use std::error;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_framework::aggregator_v2::{Self, Aggregator, AggregatorSnapshot};
    use aptos_framework::coin;
    use aptos_framework::aptos_account;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object::{Self, Object, DeleteRef, ExtendRef, TransferRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::randomness;
    use aptos_framework::timestamp;
    use addr::smarter_table::{Self, SmarterTable};
    use addr::parallel_buckets::{Self, ParallelBuckets};

    use emoji_coin::coin_factory::Emojicoin;

    const YEAR_IN_SECONDS: u64 = 31536000;
    const MAX_ENVELOPES: u64 = 8888;
    const RANDOM_ENTRIES_TO_PREGENERATE: u64 = 20;
    const NUM_PARALLEL_BUCKETS: u64 = 5;

    /// You tried to create a gift with an expiration time in the past.
    const E_GIFT_EXPIRATION_IN_PAST: u64 = 1;

    /// You tried to create a gift with an expiration time too far in the future.
    const E_GIFT_EXPIRATION_TOO_FAR_IN_FUTURE: u64 = 2;

    /// You tried to create a gift with zero envelopes.
    const E_MUST_CREATE_AT_LEAST_ONE_ENVELOPE: u64 = 3;

    /// You tried to create a gift with nothing in it.
    const E_AMOUNT_MUST_BE_GREATER_THAN_ZERO: u64 = 4;

    /// You tried to create a gift with an empty message.
    const E_MESSAGE_MUST_BE_NON_EMPTY: u64 = 5;

    /// You tried to create a gift with a message that is too long.
    const E_MESSAGE_TOO_LONG: u64 = 6;

    /// You tried to snatch a envelope from a Gift that has expired.
    const E_GIFT_EXPIRED: u64 = 7;

    /// You canoot snatch a envelope from your own gift!
    const E_SNATCHER_IS_GIFTER: u64 = 8;

    /// There are no envelopes left!
    const E_NO_ENVELOPES_LEFT: u64 = 9;

    /// You already snatched a envelope from this gift!
    const E_ALREADY_SNATCHED: u64 = 10;

    /// You tried to reclaim a Gift that hasn't expired yet or run out of envelopes / funds.
    const E_CANNOT_RECLAIM_YET: u64 = 12;

    /// Only the owner can reclaim the gift before it expires.
    const E_ONLY_OWNER_CAN_RECLAIM_EARLY: u64 = 13;

    /// You tried to create a gift with less coins than envelopes
    const E_AMOUNT_MUST_BE_GREATER_THAN_ENVELOPES: u64 = 14;

    /// You tried to create a gift with too many envelopes
    const E_ENVELOPES_MUST_BE_LESS_THAN_MAX: u64 = 15;

    /// Hongbao is paused
    const E_PAUSED: u64 = 16;

    /// Not deployer
    const ENOT_DEPLOYER: u64 = 17;

    #[event]
    struct CreateGiftEvent has drop, store {
        gift_address: address,
        creator: address,
        num_envelopes: u64,
        expiration_time: u64,
        fa_metadata_address: address,
        amount: u64,
        message: String,
        // Since we don't have support for "constants" in no code indexing we instead
        // determine whether a gift has been claimed by writing is_reclaimed false here
        // and is_reclaimed true in the ReclaimGiftEvent.
        is_reclaimed: bool,
        // Similarly, since we can't define a default value for a field, we set this
        // field to zero here and update it in the ReclaimGiftEvent.
        reclaimed_amount: u64
    }

    #[event]
    struct ClaimEnvelopeEvent has drop, store {
        gift_address: address,
        recipient: address,
        fa_metadata_address: address,
        snatched_amount: u64,
        // Useful for indexing.
        remaining_envelopes: AggregatorSnapshot<u64>,
        remaining_amount: AggregatorSnapshot<u64>
    }

    #[event]
    struct ReclaimGiftEvent has drop, store {
        gift_address: address,
        creator: address,
        reclaimed_amount: u64,
        // Useful for indexing. See the matching comment in CreateGiftEvent.
        is_reclaimed: bool
    }

    /// This contains all the information relevant to a single Gift. A single Gift is
    /// disbursed as many envelopes, matching how it works irl / in other apps. The
    /// actual asset isn't here. Instead, this Gift goes into an object that also owns
    /// a fungible store.
    struct Gift has key, store {
        /// These are all the addresses that have taken a envelope from this gift.
        /// The value doesn't mean anything, we only care about the keys. We just use
        /// this because there is no set type in Move.
        recipients: Recipients,

        /// The total number of envelopes in this Gift.
        num_envelopes: u64,

        /// The number of envelopes that have not been snatched yet.
        /// This is an aggregator so we can allow for parallelism
        num_envelopes_remaining: Aggregator<u64>,

        /// The number of coins that have not been snatched yet.
        /// This is an aggregator so we can allow for parallelism
        coins_remaining: Aggregator<u64>,

        /// When the Gift expires. Before this point, only the owner of the gift can
        /// reclaim the funds. Afterwards, anyone can call reclaim. Unixtime in seconds.
        expiration_time: u64,

        /// This tells us what FA this gift holds.
        fa_metadata: Object<Metadata>,

        /// A message the creator wants to show to the snatchers.
        message: String,

        /// When creating the gift, the creator can set this to ensure that only people
        /// with the / paylink can snatch a envelope. This is the public key.
        paylink_verification_key: Option<vector<u8>>,

        /// If true, only keyless accounts can snatch a envelope.
        keyless_only: bool,

        /// Parallel buckets for the pre-generated gifts
        parallel_buckets: ParallelBuckets<u64>,

        // Refs for the object. We don't use the transfer ref but we keep one just in
        // case we need it later for some future feature.
        extend_ref: ExtendRef,
        transfer_ref: TransferRef,
        delete_ref: DeleteRef
    }

    // We use an enum so we can update to BigOrderedMap later.
    enum Recipients has store {
        RecipientsSmartTable {
            recipients: SmarterTable<address, bool>
        }
    }

    struct Config has key {
        paused: bool
    }

    /// Pause claiming and creating gifts
    public entry fun set_paused(caller: &signer, pause: bool) acquires Config {
        assert!(
            signer::address_of(caller) == @addr,
            error::permission_denied(ENOT_DEPLOYER)
        );

        if (exists<Config>(@addr)) {
            let config = borrow_global_mut<Config>(@addr);
            config.paused = pause;
        } else {
            let config = Config { paused: pause };
            move_to(caller, config);
        }
    }

    /// This works for coins / migrated coins. We convert the coin into an FA and then
    /// call create_gift.
    public entry fun create_gift_coin<CoinType>(
        caller: &signer,
        num_envelopes: u64,
        expiration_time: u64,
        // The amount of the coin to put in the gift. This should be OCTAS or whatever
        // the equivalent is for the asset.
        amount: u64,
        message: String,
        paylink_verification_key: Option<vector<u8>>,
        keyless_only: bool
    ) acquires Config {
        let coin = coin::withdraw<CoinType>(caller, amount);
        let fa = coin::coin_to_fungible_asset(coin);
        create_gift(
            caller,
            num_envelopes,
            expiration_time,
            fa,
            message,
            paylink_verification_key,
            keyless_only
        );
    }

    /// For creating a gift with an asset that has only ever been an FA, use this.
    public entry fun create_gift_fa(
        caller: &signer,
        num_envelopes: u64,
        expiration_time: u64,
        // The amount of the FA to put in the gift. This should be OCTAS or whatever
        // the equivalent is for the asset.
        amount: u64,
        // The metadata describing which FA we're using.
        fa_metadata: Object<Metadata>,
        message: String,
        paylink_verification_key: Option<vector<u8>>,
        keyless_only: bool
    ) acquires Config {
        // Withdraw the funds from the user.
        let fa = primary_fungible_store::withdraw(caller, fa_metadata, amount);
        create_gift(
            caller,
            num_envelopes,
            expiration_time,
            fa,
            message,
            paylink_verification_key,
            keyless_only
        );
    }

    public fun create_gift(
        caller: &signer,
        num_envelopes: u64,
        expiration_time: u64,
        // The asset we took from the caller.
        fa: FungibleAsset,
        message: String,
        paylink_verification_key: Option<vector<u8>>,
        keyless_only: bool
    ): Object<Gift> acquires Config {
        let caller_address = signer::address_of(caller);

        // Make sure Hongbao is not paused
        assert!(!paused(), error::invalid_state(E_PAUSED));

        // Make sure the expiration time is at least 10 seconds in the future.
        assert!(
            expiration_time > timestamp::now_seconds() + 10,
            error::invalid_state(E_GIFT_EXPIRATION_IN_PAST)
        );

        // Make sure the expiration time isn't too far in the future.
        assert!(
            expiration_time < timestamp::now_seconds() + YEAR_IN_SECONDS,
            error::invalid_state(E_GIFT_EXPIRATION_TOO_FAR_IN_FUTURE)
        );

        // Make sure there is at least one envelope.
        assert!(
            num_envelopes > 0,
            error::invalid_state(E_MUST_CREATE_AT_LEAST_ONE_ENVELOPE)
        );

        // Assert the amount is not zero.
        let amount = fungible_asset::amount(&fa);
        assert!(amount > 0, error::invalid_state(E_AMOUNT_MUST_BE_GREATER_THAN_ZERO));

        // Assert the amount is greater than or equal to the number of envelopes.
        assert!(
            amount >= num_envelopes,
            error::invalid_state(E_AMOUNT_MUST_BE_GREATER_THAN_ENVELOPES)
        );

        // Assert the number of envelopes is less than the max
        assert!(
            num_envelopes <= MAX_ENVELOPES,
            error::invalid_state(E_ENVELOPES_MUST_BE_LESS_THAN_MAX)
        );

        // Assert the message is not empty.
        assert!(
            message.length() > 0,
            error::invalid_state(E_MESSAGE_MUST_BE_NON_EMPTY)
        );

        // Assert the message is not too long.
        assert!(message.length() < 280, error::invalid_state(E_MESSAGE_TOO_LONG));

        // Create an object to hold the gift.
        let constructor_ref = &object::create_object(caller_address);

        // We generate an extend ref and transfer ref just in case we need them for
        // some future feature.
        let extend_ref = object::generate_extend_ref(constructor_ref);
        let transfer_ref = object::generate_transfer_ref(constructor_ref);

        // We need this for reclaiming the gift at the end, in which we delete the
        // object too.
        let delete_ref = object::generate_delete_ref(constructor_ref);

        // We store this so we know what asset we're dealing with.
        let fa_metadata = fungible_asset::metadata_from_asset(&fa);

        // If the paylink verification key is set, validate it.
        if (paylink_verification_key.is_some()) {
            paylink::assert_valid_paylink_verification_key(
                paylink_verification_key.borrow()
            );
        };

        let num_recipient_buckets = if (num_envelopes > 20) { 10 }
        else { 1 };

        // Create the Gift itself.
        let gift = Gift {
            recipients: Recipients::RecipientsSmartTable {
                recipients: smarter_table::new(num_recipient_buckets)
            },
            num_envelopes,
            num_envelopes_remaining: aggregator_v2::create_unbounded_aggregator_with_value<u64>(
                num_envelopes
            ),
            coins_remaining: aggregator_v2::create_unbounded_aggregator_with_value<u64>(
                num_envelopes
            ),
            expiration_time,
            fa_metadata,
            message,
            paylink_verification_key,
            keyless_only,
            parallel_buckets: parallel_buckets::new(NUM_PARALLEL_BUCKETS),
            extend_ref,
            transfer_ref,
            delete_ref
        };

        // Store it on the object.
        let gift_signer = object::generate_signer(constructor_ref);
        move_to(&gift_signer, gift);

        // Deposit the funds from the caller into the FA store owned by the gift.
        let gift_address = object::address_from_constructor_ref(constructor_ref);
        primary_fungible_store::deposit(gift_address, fa);

        event::emit(
            CreateGiftEvent {
                gift_address,
                creator: caller_address,
                num_envelopes,
                expiration_time,
                fa_metadata_address: object::object_address(&fa_metadata),
                amount,
                message,
                is_reclaimed: false,
                // Dummy value for now.
                reclaimed_amount: 0
            }
        );

        // Return the gift object. This is useful for testing.
        object::object_from_constructor_ref(constructor_ref)
    }

    #[randomness]
    /// People can call this function to try and snatch a envelope from the Gift.
    ///
    /// If the paylink verification key is set, the snatcher must provide a signed
    /// message that corresponds to the paylink verification key. If it's not set,
    /// the snatcher can just send in an empty vector.
    ///
    /// The caller must also pass in their public key so we can validate that the
    /// caller is a keyless account if `keyless_only` is true. If `keyless_only`
    /// is false, the caller can also just pass in an empty vector for
    /// `public_key_bytes`.
    ///
    /// This is a private entry function because public entry functions with randomness
    /// can possibly be exploited.
    entry fun snatch_envelope(
        caller: &signer,
        gift: Object<Gift>,
        signed_message_bytes: vector<u8>,
        public_key_bytes: vector<u8>
    ) acquires Config, Gift {
        let caller_address = signer::address_of(caller);

        let gift_address = object::object_address(&gift);
        let gift_ = borrow_global_mut<Gift>(gift_address);

        // Make sure the snatcher is not the person who created the gift.
        assert!(
            !object::is_owner(gift, caller_address),
            error::invalid_state(E_SNATCHER_IS_GIFTER)
        );

        // Make sure the Gift hasn't expired.
        assert!(
            timestamp::now_seconds() < gift_.expiration_time,
            error::invalid_state(E_GIFT_EXPIRED)
        );

        // Make sure Hongbao is not paused
        assert!(!paused(), error::invalid_state(E_PAUSED));

        // Make sure there are still envelopes left.
        assert!(
            aggregator_v2::is_at_least(&gift_.num_envelopes_remaining, 1),
            error::invalid_state(E_NO_ENVELOPES_LEFT)
        );

        // Make sure the caller hasn't already snatched a envelope.
        match(&gift_.recipients) {
            RecipientsSmartTable { recipients } => assert!(
                !recipients.contains(caller_address),
                error::invalid_state(E_ALREADY_SNATCHED)
            )
        };

        // If the paylink verification key is set, validate that the user provided a
        // valid signed message.
        if (gift_.paylink_verification_key.is_some()) {
            let gift_address = object::object_address(&gift);
            let verification_key = *gift_.paylink_verification_key.borrow();
            paylink::assert_signed_message_is_valid(
                gift_address,
                caller_address,
                verification_key,
                signed_message_bytes
            );
        };

        // If `keyless_only` is true, validate that the caller is a keyless account.
        if (gift_.keyless_only) {
            keyless::assert_is_keyless(caller_address, public_key_bytes);
        };

        // Okay, the user is allowed to snatch a envelope!

        // Get a gift signer so we can distribute funds.
        let gift_signer = object::generate_signer_for_extending(&gift_.extend_ref);

        // Subtract one from the aggregator envelopes
        aggregator_v2::sub(&mut gift_.num_envelopes_remaining, 1);

        // Determine how much to give the snatcher. They can randomly get anything from
        // nothing to the maximum amount in the gift. This means it's possible for a
        // snatcher to snatch a envelope with nothing in it. They'll likely just bail
        // and eventually the creator will reclaim the gift, which is still worth it
        // for the gas refund.
        //
        // We do +1 because the end of the range is exclusive.
        //
        // If there is only 1 envelope left, the snatcher gets whatever is left.
        let amount =
            if (!aggregator_v2::is_at_least(&gift_.num_envelopes_remaining, 1)) {
                primary_fungible_store::balance(gift_address, gift_.fa_metadata)
            } else {
                // Try to get one from our bucket
                let envelope_amount =
                    gift_.parallel_buckets.pop(randomness::u64_integer());
                if (envelope_amount.is_none()) {
                    // Time to fill up the buckets!
                    // THIS IS WHAT FULLY BREAKS PARALLELISM
                    let envelopes = vector::empty();
                    let remaining_amount =
                        primary_fungible_store::balance(gift_address, gift_.fa_metadata);
                    let remaining_packets = remaining_envelopes(gift_);
                    for (_i in 0..RANDOM_ENTRIES_TO_PREGENERATE) {
                        let amount =
                            dirichlet::sequential_dirichlet_hongbao(
                                remaining_amount, remaining_packets
                            );
                        envelopes.push_back(amount);
                    };
                    let amount = envelopes.pop_back();
                    gift_.parallel_buckets.add_many_evenly(
                        envelopes, randomness::u64_integer()
                    );
                    amount
                } else {
                    envelope_amount.destroy_some()
                }
            };

        // Subtract the amount from the aggregator.
        aggregator_v2::sub(&mut gift_.coins_remaining, amount);

        // Transfer the amount from the FA store.
        transfer_gift(
            &gift_signer,
            gift_.fa_metadata,
            caller_address,
            amount
        );

        // Mark the snatcher as having snatched a envelope.
        match(&mut gift_.recipients) {
            RecipientsSmartTable { recipients } => recipients.add(caller_address, true)
        };

        event::emit(
            ClaimEnvelopeEvent {
                gift_address,
                recipient: caller_address,
                fa_metadata_address: object::object_address(&gift_.fa_metadata),
                snatched_amount: amount,
                remaining_envelopes: aggregator_v2::snapshot(
                    &gift_.num_envelopes_remaining
                ),
                remaining_amount: aggregator_v2::snapshot(&gift_.coins_remaining)
            }
        );
    }

    /// When called this sends the remaining balance back to the owner. Whoever calls
    /// this gets the gas refund. You can only call this once the gift has expired or
    /// there are no envelopes left.
    ///
    /// To reclaim early as the gift owner, call `reclaim_gift_as_owner`.
    public entry fun reclaim_gift(gift: Object<Gift>) acquires Gift {
        let gift_address = object::object_address(&gift);
        let gift_ = borrow_global<Gift>(gift_address);

        // Make sure either the gift has expired or there are no envelopes left.
        assert!(
            timestamp::now_seconds() >= gift_.expiration_time
                || remaining_envelopes(gift_) == 0,
            error::invalid_state(E_CANNOT_RECLAIM_YET)
        );

        reclaim_gift_inner(gift);
    }

    // These next two functions exist purely to avoid having to redeploy. In a perfect
    // world, we only need a single reclaim_gift function:
    // https://gist.github.com/banool/e01679d8c6522981d021c9f00555fe1f

    /// When called this sends the remaining balance back to the owner. Whoever calls
    /// this gets the gas refund. The owner can call this at any time.
    public entry fun reclaim_gift_as_owner(
        caller: &signer, gift: Object<Gift>
    ) acquires Gift {
        let caller_address = signer::address_of(caller);
        assert!(
            object::is_owner(gift, caller_address),
            error::invalid_state(E_ONLY_OWNER_CAN_RECLAIM_EARLY)
        );
        reclaim_gift_inner(gift);
    }

    fun reclaim_gift_inner(gift: Object<Gift>) acquires Gift {
        let gift_owner_address = object::owner(gift);

        // We destroy the object at the end of this function, so we don't just borrow
        // the gift, we remove it entirely.
        let gift_address = object::object_address(&gift);
        let gift_ = move_from<Gift>(gift_address);

        // Get the remaining balance.
        let balance = primary_fungible_store::balance(gift_address, gift_.fa_metadata);

        if (balance > 0) {
            // Transfer the balance back to the owner of the gift.
            let gift_signer = object::generate_signer_for_extending(&gift_.extend_ref);
            transfer_gift(
                &gift_signer,
                gift_.fa_metadata,
                gift_owner_address,
                balance
            );
        };

        // Now we clean up. First, destructure the gift.
        let Gift {
            recipients,
            num_envelopes: _num_envelopes,
            expiration_time: _expiration_time,
            fa_metadata: _fa_metadata,
            message: _message,
            paylink_verification_key: _paylink_verification_key,
            num_envelopes_remaining: _,
            coins_remaining: _,
            parallel_buckets,
            keyless_only: _keyless_only,
            extend_ref: _extend_ref,
            transfer_ref: _transfer_ref,
            delete_ref
        } = gift_;

        parallel_buckets.destroy();

        match(recipients) {
            RecipientsSmartTable { recipients } => recipients.destroy()
        };

        // Delete the object.
        object::delete(delete_ref);

        event::emit(
            ReclaimGiftEvent {
                gift_address,
                creator: gift_owner_address,
                reclaimed_amount: balance,
                is_reclaimed: true
            }
        );
    }

    /// Get the number of remaining envelopes in the gift.
    inline fun remaining_envelopes(gift_: &Gift): u64 {
        let len =
            match(&gift_.recipients) {
                RecipientsSmartTable { recipients } => recipients.size()
            };
        gift_.num_envelopes - len
    }

    inline fun transfer_gift(
        signer: &signer,
        gift_metadata: Object<Metadata>,
        caller_address: address,
        amount: u64
    ) {
        let fa_metadata_address = object::object_address(&gift_metadata);
        // for hongbao and APT, only transfer coin to avoid many new FA's going around
        if (fa_metadata_address == @0xa) {
            aptos_account::transfer_coins<0x1::aptos_coin::AptosCoin>(
                signer, caller_address, amount
            );
        } else if (fa_metadata_address
            == @0x180e877b151107d7d180545c2fdb373578740872a59071f636c62bd60a6b249d) {
            // Hongbao emoji on mainnet
            aptos_account::transfer_coins<Emojicoin>(signer, caller_address, amount);
        } else {
            primary_fungible_store::transfer(
                signer, gift_metadata, caller_address, amount
            );
        };
    }

    // ////////////////////////////////////////////////////////////////////////////////
    // View functions
    // ////////////////////////////////////////////////////////////////////////////////

    #[view]
    public fun paused(): bool acquires Config {
        if (exists<Config>(@addr)) {
            let config = borrow_global<Config>(@addr);
            return config.paused
        };
        false
    }

    // ////////////////////////////////////////////////////////////////////////////////
    // Tests
    // ////////////////////////////////////////////////////////////////////////////////

    #[test_only]
    use aptos_std::option;
    #[test_only]
    use aptos_std::string;
    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::aptos_coin::AptosCoin;
    #[test_only]
    use aptos_framework::coin::MintCapability;

    #[test_only]
    const E_TEST_FAILURE: u64 = 100000;
    #[test_only]
    const DEFAULT_STARTING_BALANCE: u64 = 10000;

    #[test_only]
    public fun set_up_testing_time_env(
        aptos_framework: &signer, timestamp: u64
    ) {
        // set up global time for testing purpose
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(timestamp);
    }

    #[test_only]
    fun get_mint_cap(aptos_framework: &signer): MintCapability<AptosCoin> {
        let (burn_cap, freeze_cap, mint_cap) =
            coin::initialize<AptosCoin>(
                aptos_framework,
                string::utf8(b"TC"),
                string::utf8(b"TC"),
                8,
                false
            );
        coin::destroy_freeze_cap(freeze_cap);
        coin::destroy_burn_cap(burn_cap);
        mint_cap
    }

    #[test_only]
    fun create_test_account(
        mint_cap: &MintCapability<AptosCoin>, account: &signer
    ) {
        account::create_account_for_test(signer::address_of(account));
        coin::register<AptosCoin>(account);
        let coins = coin::mint<AptosCoin>(DEFAULT_STARTING_BALANCE, mint_cap);
        coin::deposit(signer::address_of(account), coins);
    }

    #[test_only]
    /// Call this at the start of each test.
    fun initialize(
        creator: &signer,
        snatcher1: &signer,
        snatcher2: &signer,
        aptos_framework: &signer
    ) {
        let mint_cap = get_mint_cap(aptos_framework);
        coin::create_coin_conversion_map(aptos_framework);
        coin::create_pairing<AptosCoin>(aptos_framework);
        randomness::initialize_for_testing(aptos_framework);
        set_up_testing_time_env(aptos_framework, 10);
        create_test_account(&mint_cap, creator);
        create_test_account(&mint_cap, snatcher1);
        create_test_account(&mint_cap, snatcher2);
        coin::destroy_mint_cap(mint_cap);
    }

    #[
        test(
            creator = @0x987,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[lint::allow_unsafe_randomness]
    public entry fun test_basic_happy_path(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );
        let snatcher1_address = signer::address_of(&snatcher1);
        let snatcher2_address = signer::address_of(&snatcher2);

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                5,
                100,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch as snatcher 1 and assert their balance has increased.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher1_address) > DEFAULT_STARTING_BALANCE, 0
        );

        // Snatch as snatcher 2 and assert their balance has increased.
        snatch_envelope(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher2_address) > DEFAULT_STARTING_BALANCE, 0
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196609, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_gift_expired_in_past(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift. This should fail because the expiration time is in the past.
        create_gift(
            &creator,
            5,
            0,
            fa,
            string::utf8(b"hey friends"),
            option::none(),
            false
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196622, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_amount_less_than_envelopes(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift. This should fail because the number of envelopes is bigger than amount.
        create_gift(
            &creator,
            5,
            100,
            fa,
            string::utf8(b"hey friends"),
            option::none(),
            false
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196623, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_envelopes_greater_than_max(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, MAX_ENVELOPES + 10);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift. This should fail because the num of envelopes is bigger than max.
        create_gift(
            &creator,
            MAX_ENVELOPES + 1,
            100,
            fa,
            string::utf8(b"hey friends"),
            option::none(),
            false
        );
    }

    // Try running this without the expected_failure. Ensure it only fails on the
    // second attempt to snatch_envelope.
    // TODO: Find a programmatic way to assert this.
    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196615, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_snatch_expired(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                5,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Fast forward time to just before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that snatching succeeds.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to the expiration.
        timestamp::update_global_time_for_test_secs(25);

        // See that snatching fails.
        snatch_envelope(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196618, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_snatch_twice(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                5,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // See that snatching succeeds.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // See that the same person trying to snatch a second time fails.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196616, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_snatcher_is_gifter(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                5,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // See that the creator cannot snatch a envelope.
        snatch_envelope(
            &creator,
            gift,
            vector::empty(),
            vector::empty()
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196617, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_no_envelopes_left(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                2,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // See that the first two snatches succeed..
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        snatch_envelope(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );

        // See that the third snatch fails.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[lint::allow_unsafe_randomness]
    public entry fun test_reclaim_all_claimed(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                2,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );
        let gift_address = object::object_address(&gift);

        // Snatch all the envelopes
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        snatch_envelope(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Reclaim the gift.
        reclaim_gift(gift);

        // See that the gift is deleted.
        assert!(!object::object_exists<Gift>(gift_address), E_TEST_FAILURE);
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[lint::allow_unsafe_randomness]
    public entry fun test_reclaim_expired(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                2,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );
        let gift_address = object::object_address(&gift);

        // Snatch one of the envelopes
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to the expiration.
        timestamp::update_global_time_for_test_secs(25);

        // Reclaim the gift. See that anyone can do it.
        reclaim_gift(gift);

        // See that the gift is deleted.
        assert!(!object::object_exists<Gift>(gift_address), E_TEST_FAILURE);
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196621, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_reclaim_as_owner_not_as_owner(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                2,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch only one of the envelopes.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that reclaiming the gift fails if you're not the owner.
        reclaim_gift_as_owner(&snatcher1, gift);
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196620, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_reclaim_before_expiration_not_as_owner(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                2,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch only one of the envelopes.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that reclaiming the gift fails before the expiration with `reclaim_gift`.
        reclaim_gift(gift);
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[lint::allow_unsafe_randomness]
    public entry fun test_reclaim_before_expiration_as_owner(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                2,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch only one of the envelopes.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that you can reclaim the gift at any time if you're the owner.
        reclaim_gift_as_owner(&creator, gift);
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196611, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_create_gift_zero_envelopes(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // This should fail with E_MUST_CREATE_AT_LEAST_ONE_ENVELOPE
        create_gift(
            &creator,
            0,
            25,
            fa,
            string::utf8(b"hey friends"),
            option::none(),
            false
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196610, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_create_gift_expiration_too_far(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // This should fail because the expiration time is too far out.
        let now = timestamp::now_seconds();
        let too_far_expiration = now + YEAR_IN_SECONDS + 1;
        create_gift(
            &creator,
            5,
            too_far_expiration,
            fa,
            string::utf8(b"hey friends"),
            option::none(),
            false
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 65636, location = addr::paylink)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_paylink_invalid_verification_key(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Create an invalid verification key (public key length is not 32 bytes).
        let verification_key = vector::empty<u8>();
        verification_key.push_back(3u8);

        // See that creating a gift fails.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);
        create_gift(
            &creator,
            5,
            25,
            fa,
            string::utf8(b"hey friends"),
            option::some(verification_key),
            false
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 65538, location = aptos_framework::ed25519)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_paylink_invalid_signed_message(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Generate a key pair.
        let (_sk, vpk) = aptos_framework::ed25519::generate_keys();
        let verification_key =
            aptos_framework::ed25519::validated_public_key_to_bytes(&vpk);

        // Create a Gift that requires that you know the paylink private key.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);
        let gift =
            create_gift(
                &creator,
                5,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::some(verification_key),
                false
            );

        // This should fail because the empty vector is not a valid signed message.
        let signed_message = vector::empty<u8>();
        snatch_envelope(
            &snatcher1,
            gift,
            signed_message,
            vector::empty()
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[lint::allow_unsafe_randomness]
    public entry fun test_paylink_happy_path(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );
        let snatcher1_address = signer::address_of(&snatcher1);

        // Generate a key pair.
        let (sk, vpk) = aptos_framework::ed25519::generate_keys();
        let verification_key =
            aptos_framework::ed25519::validated_public_key_to_bytes(&vpk);

        // Create a Gift that requires that you know the paylink private key.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);
        let gift =
            create_gift(
                &creator,
                5,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::some(verification_key),
                false
            );
        let gift_address = object::object_address(&gift);

        // Prepare the expected signed message.
        let message = paylink::build_claim_message(gift_address, snatcher1_address);

        // Sign it and get the signature as bytes.
        let signature = aptos_framework::ed25519::sign_struct(&sk, message);
        let signed_message = aptos_framework::ed25519::signature_to_bytes(&signature);

        snatch_envelope(
            &snatcher1,
            gift,
            signed_message,
            vector::empty()
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 65736, location = addr::keyless)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_keyless_unhappy_path(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // Create a Gift that only keyless accounts can snatch
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);
        let gift =
            create_gift(
                &creator,
                5,
                25,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                true /* keyless_only */
            );

        // This should fail because the empty vector is not a valid public key.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
    }

    #[
        test(
            deployer = @addr,
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196624, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_paused_create(
        deployer: signer,
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );
        let snatcher1_address = signer::address_of(&snatcher1);
        let snatcher2_address = signer::address_of(&snatcher2);

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        set_paused(&deployer, true);
        assert!(paused() == true, 0);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                5,
                100,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch as snatcher 1 and assert their balance has increased.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher1_address) > DEFAULT_STARTING_BALANCE, 0
        );

        // Snatch as snatcher 2 and assert their balance has increased.
        snatch_envelope(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher2_address) > DEFAULT_STARTING_BALANCE, 0
        );
    }

    #[
        test(
            deployer = @addr,
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[expected_failure(abort_code = 196624, location = Self)]
    #[lint::allow_unsafe_randomness]
    public entry fun test_paused_claim(
        deployer: signer,
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) acquires Config, Gift {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );
        let snatcher1_address = signer::address_of(&snatcher1);

        // Get funds for the gift.
        let coin = coin::withdraw<AptosCoin>(&creator, 1000);
        let fa = coin::coin_to_fungible_asset(coin);

        // Create the gift.
        let gift =
            create_gift(
                &creator,
                5,
                100,
                fa,
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        set_paused(&deployer, true);
        assert!(paused() == true, 0);

        // Snatch as snatcher 1 and assert their balance has increased.
        snatch_envelope(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher1_address) > DEFAULT_STARTING_BALANCE, 0
        );
    }

    #[
        test(
            creator = @0x123,
            snatcher1 = @0x100,
            snatcher2 = @0x101,
            aptos_framework = @aptos_framework
        )
    ]
    #[lint::allow_unsafe_randomness]
    public entry fun test_keyless_happy_path(
        creator: signer,
        snatcher1: signer,
        snatcher2: signer,
        aptos_framework: signer
    ) {
        initialize(
            &creator,
            &snatcher1,
            &snatcher2,
            &aptos_framework
        );

        // TODO
    }
}
