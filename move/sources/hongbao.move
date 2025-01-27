/// Many entry functions that operate against an existing gift require a CoinType
/// generic type param. If you know the Gift contains an FA you can use
/// a dummy CoinType, e.g. something that isn't even a coin like
/// `aptos_framework::timestamp::CurrentTimeMicroseconds`. If the gift contains a
/// Coin, you need the real CoinType, e.g. `aptos_framework::coin::AptosCoin`.
///
/// We make the asset type readily available to the frontend by indexing it, since we
/// emit the asset type in the CreateGiftEvent.

module addr::hongbao {
    use addr::keyless;
    use addr::paylink;
    use addr::dirichlet;
    use addr::smarter_table::{Self, SmarterTable};
    use addr::parallel_buckets::{Self, ParallelBuckets};
    use std::error;
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_std::math64;
    use aptos_std::type_info;
    use aptos_framework::aptos_account;
    use aptos_framework::aggregator_v2::{Self, Aggregator, AggregatorSnapshot};
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object::{Self, Object, DeleteRef, ExtendRef, TransferRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::randomness;
    use aptos_framework::timestamp;

    const YEAR_IN_SECONDS: u64 = 31536000;
    const MAX_ENVELOPES: u64 = 8888;
    const RANDOM_ENTRIES_TO_PREGENERATE: u64 = 200;

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

    /// You tried to reclaim a Gift that hasn't expired yet or run out of envelopes / funds and you're not the owner of the gift.
    const E_CANNOT_RECLAIM_YET: u64 = 12;

    /// You tried to create a gift with less coins than envelopes
    const E_AMOUNT_MUST_BE_GREATER_THAN_ENVELOPES: u64 = 14;

    /// You tried to create a gift with too many envelopes
    const E_ENVELOPES_MUST_BE_LESS_THAN_MAX: u64 = 15;

    /// Hongbao is paused!
    const E_PAUSED: u64 = 16;

    /// You are not the deployer of the contract.
    const E_NOT_DEPLOYER: u64 = 17;

    #[event]
    struct CreateGiftEvent has drop, store {
        gift_address: address,
        creator: address,
        num_envelopes: u64,
        expiration_time: u64,
        // This is the FA metadata address for the asset.
        fa_metadata_address: address,
        // If the gift was created with `create_gift_coin`, this will be a proper value.
        // If not, it will be an empty string (no code indexing doesn't support Option
        // at the moment). If this is a real value, the client should use this for
        // functions that take a CoinType. If this is an empty string, the client can
        // use a dummy CoinType, e.g.
        // `aptos_framework::timestamp::CurrentTimeMicroseconds`.
        coin_type: String,
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
        // See the comment in `CreateGiftEvent`.
        coin_type: String,
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
    /// disbursed as many envelopes, matching how it works irl / in other apps.
    ///
    /// See the comment for GiftAsset for more details about how the asset is stored
    /// and why we need the generic type param.
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

        /// This tells us what asset this gift holds.
        fa_metadata: Object<Metadata>,

        /// This is true if the asset used to create the gift was originally a coin
        /// that we converted to an FA. It will be false if it was always an FA.
        ///
        /// If this is true, when people snatch / reclaim, we send it back as a Coin.
        original_asset_was_coin: bool,

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
            error::permission_denied(E_NOT_DEPLOYER)
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
    /// call create_gift. When the user snatches / the owner reclaims, we give the user
    /// the asset back as a Coin.
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
        create_gift_internal(
            caller,
            num_envelopes,
            expiration_time,
            fa,
            option::some(type_info::type_name<CoinType>()),
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
        let fa = primary_fungible_store::withdraw(caller, fa_metadata, amount);
        // We use a dummy type for the CoinType.
        create_gift_internal(
            caller,
            num_envelopes,
            expiration_time,
            fa,
            option::none(),
            message,
            paylink_verification_key,
            keyless_only
        );
    }

    /// Deprecated. Use `create_gift_fa` or `create_gift_coin` instead.
    public fun create_gift(
        _caller: &signer,
        _num_envelopes: u64,
        _expiration_time: u64,
        // The asset we took from the caller.
        _fa: FungibleAsset,
        // If the original asset was a coin, this will be the CoinType of that coin.
        // It's okay to pass it in as a string becuase we only use it to derive other
        // values (like `original_asset_was_coin`) and emit information in events.
        _coin_type: Option<String>,
        _message: String,
        _paylink_verification_key: Option<vector<u8>>,
        _keyless_only: bool
    ): Object<Gift> {
        abort 0
    }

    fun create_gift_internal(
        caller: &signer,
        num_envelopes: u64,
        expiration_time: u64,
        // The asset we took from the caller.
        fa: FungibleAsset,
        // If the original asset was a coin, this will be the CoinType of that coin.
        // It's okay to pass it in as a string becuase we only use it to derive other
        // values (like `original_asset_was_coin`) and emit information in events.
        coin_type: Option<String>,
        message: String,
        paylink_verification_key: Option<vector<u8>>,
        keyless_only: bool
    ): Object<Gift> acquires Config {
        let caller_address = signer::address_of(caller);

        let amount = fungible_asset::amount(&fa);

        // Assert the amount is not zero.
        assert!(amount > 0, error::invalid_state(E_AMOUNT_MUST_BE_GREATER_THAN_ZERO));

        // Assert the amount is greater than or equal to the number of envelopes.
        assert!(
            amount >= num_envelopes,
            error::invalid_state(E_AMOUNT_MUST_BE_GREATER_THAN_ENVELOPES)
        );

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

        // If the paylink verification key is set, validate it.
        if (paylink_verification_key.is_some()) {
            paylink::assert_valid_paylink_verification_key(
                paylink_verification_key.borrow()
            );
        };

        // Create an object to hold the gift.
        let constructor_ref = &object::create_object(caller_address);

        // We generate an extend ref and transfer ref just in case we need them for
        // some future feature.
        let extend_ref = object::generate_extend_ref(constructor_ref);
        let transfer_ref = object::generate_transfer_ref(constructor_ref);

        // We need this for reclaiming the gift at the end, in which we delete the
        // object too.
        let delete_ref = object::generate_delete_ref(constructor_ref);

        let gift_signer = object::generate_signer(constructor_ref);
        let gift_address = object::address_from_constructor_ref(constructor_ref);

        // Get the FA metadata.
        let fa_metadata = fungible_asset::metadata_from_asset(&fa);

        // Deposit the funds from the caller into the FA store owned by the gift.
        let primary_store =
            primary_fungible_store::create_primary_store(gift_address, fa_metadata);
        fungible_asset::upgrade_store_to_concurrent(&gift_signer, primary_store);
        primary_fungible_store::deposit(gift_address, fa);

        let num_recipient_buckets =
            if (num_envelopes > 500) { 40 }
            else if (num_envelopes > 200) { 20 }
            else if (num_envelopes > 20) { 5 }
            else { 1 };

        let original_asset_was_coin = coin_type.is_some();

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
                amount
            ),
            expiration_time,
            fa_metadata,
            original_asset_was_coin,
            message,
            paylink_verification_key,
            keyless_only,
            parallel_buckets: parallel_buckets::new(num_recipient_buckets),
            extend_ref,
            transfer_ref,
            delete_ref
        };

        // Store it on the object.
        move_to(&gift_signer, gift);

        let coin_type =
            if (coin_type.is_some()) {
                coin_type.extract()
            } else {
                string::utf8(b"")
            };
        event::emit(
            CreateGiftEvent {
                gift_address,
                creator: caller_address,
                num_envelopes,
                expiration_time,
                fa_metadata_address: object::object_address(&fa_metadata),
                coin_type,
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
    ///
    /// If the gift was created with `create_gift_coin`, the client will need to know
    /// the CoinType so it can pass it in when claiming the gift. We include that
    /// information in the `CreateGiftEvent`. If the asset was always an FA, the client
    /// can just pass a dummy type.
    entry fun snatch_envelope<CoinType>(
        caller: &signer,
        // Dummy type.
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
                    let to_generate =
                        math64::min(remaining_packets, RANDOM_ENTRIES_TO_PREGENERATE);
                    for (_i in 0..to_generate) {
                        let amount =
                            dirichlet::sequential_dirichlet_hongbao(
                                remaining_amount, remaining_packets
                            );
                        envelopes.push_back(amount);
                        remaining_amount = remaining_amount - amount;
                        remaining_packets = remaining_packets - 1;
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
        transfer_gift<CoinType>(&gift_signer, gift_, caller_address, amount);

        // Mark the snatcher as having snatched a envelope.
        match(&mut gift_.recipients) {
            RecipientsSmartTable { recipients } => recipients.add(caller_address, true)
        };

        let coin_type =
            if (gift_.original_asset_was_coin) {
                type_info::type_name<CoinType>()
            } else {
                string::utf8(b"")
            };

        event::emit(
            ClaimEnvelopeEvent {
                gift_address,
                recipient: caller_address,
                fa_metadata_address: object::object_address(&gift_.fa_metadata),
                coin_type,
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
    /// there are no envelopes left, unless you are the owner of the gift.
    ///
    /// If the gift was created with `create_gift_coin`, this will send the remaining
    /// balance back to the owner as a Coin.
    public entry fun reclaim_gift<CoinType>(
        caller: &signer, gift: Object<Gift>
    ) acquires Gift, Config {
        let gift_address = object::object_address(&gift);
        let gift_ = borrow_global<Gift>(gift_address);
        let caller_address = signer::address_of(caller);
        let gift_owner_address = object::owner(gift);

        // Make sure either:
        // 1. The caller is the owner (they can reclaim anytime), or
        // 2. The gift has expired or there are no envelopes left (anyone can reclaim)
        assert!(
            gift_owner_address == caller_address
                || timestamp::now_seconds() >= gift_.expiration_time
                || remaining_envelopes(gift_) == 0,
            error::invalid_state(E_CANNOT_RECLAIM_YET)
        );

        // We destroy the object at the end of this function, so we don't just borrow
        // the gift, we remove it entirely.
        let gift_ = move_from<Gift>(gift_address);

        // Make sure Hongbao is not paused
        assert!(!paused(), error::invalid_state(E_PAUSED));

        // Get the remaining balance.
        let balance = primary_fungible_store::balance(gift_address, gift_.fa_metadata);

        if (balance > 0) {
            // Transfer the balance back to the owner of the gift.
            let gift_signer = object::generate_signer_for_extending(&gift_.extend_ref);
            transfer_gift<CoinType>(
                &gift_signer,
                &gift_,
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
            original_asset_was_coin: _original_asset_was_coin,
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

    inline fun transfer_gift<CoinType>(
        gift_signer: &signer,
        gift_: &Gift,
        recipient_address: address,
        amount: u64
    ) {
        if (gift_.original_asset_was_coin) {
            aptos_account::transfer_coins<CoinType>(
                gift_signer, recipient_address, amount
            );
        } else {
            primary_fungible_store::transfer(
                gift_signer,
                gift_.fa_metadata,
                recipient_address,
                amount
            );
        }
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

    // Unless stated otherwise, for all tests we test the case where the asset is an FA,
    // aka original_asset_was_coin is false. So we use a dummy CoinType for functions
    // that take a CoinType in those tests.

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::aptos_coin::AptosCoin;
    #[test_only]
    use aptos_framework::coin::MintCapability;
    #[test_only]
    use aptos_framework::timestamp::CurrentTimeMicroseconds;

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
        let fa_metadata = fungible_asset::metadata_from_asset(&fa);

        // Create the gift.
        let gift =
            create_gift_internal(
                &creator,
                5,
                100,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch as snatcher 1 and assert their balance has increased.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher1_address) > DEFAULT_STARTING_BALANCE, 0
        );

        // Snatch as snatcher 2 and assert their balance has increased.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher2_address) > DEFAULT_STARTING_BALANCE, 0
        );

        // Assert that the users got FA, their primary fungible store balances should
        // have increased.
        assert!(primary_fungible_store::balance(snatcher1_address, fa_metadata) > 0, 0);
        assert!(primary_fungible_store::balance(snatcher2_address, fa_metadata) > 0, 0);
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
    public entry fun test_basic_happy_path_coin(
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
        let fa_metadata = fungible_asset::metadata_from_asset(&fa);

        // Create the gift. Tell it that the original asset was a Coin.
        let gift =
            create_gift_internal(
                &creator,
                5,
                100,
                fa,
                option::some(type_info::type_name<AptosCoin>()),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch as snatcher 1 and assert their balance has increased.
        snatch_envelope<AptosCoin>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher1_address) > DEFAULT_STARTING_BALANCE, 0
        );

        // Snatch as snatcher 2 and assert their balance has increased.
        snatch_envelope<AptosCoin>(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher2_address) > DEFAULT_STARTING_BALANCE, 0
        );

        // Assert that the users actually got just Coin, their primary fungible store
        // balances should not have increased.
        assert!(primary_fungible_store::balance(snatcher1_address, fa_metadata) == 0, 0);
        assert!(primary_fungible_store::balance(snatcher2_address, fa_metadata) == 0, 0);
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
        create_gift_internal(
            &creator,
            5,
            0,
            fa,
            option::none(),
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
        create_gift_internal(
            &creator,
            5,
            100,
            fa,
            option::none(),
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
        create_gift_internal(
            &creator,
            MAX_ENVELOPES + 1,
            100,
            fa,
            option::none(),
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
            create_gift_internal(
                &creator,
                5,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Fast forward time to just before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that snatching succeeds.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to the expiration.
        timestamp::update_global_time_for_test_secs(25);

        // See that snatching fails.
        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                5,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // See that snatching succeeds.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // See that the same person trying to snatch a second time fails.
        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                5,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // See that the creator cannot snatch a envelope.
        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                2,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // See that the first two snatches succeed..
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );

        // See that the third snatch fails.
        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                2,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );
        let gift_address = object::object_address(&gift);

        // Snatch all the envelopes
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher2,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Reclaim the gift.
        reclaim_gift<CurrentTimeMicroseconds>(&snatcher1, gift);

        // See that the gift is deleted.
        assert!(
            !object::object_exists<Gift>(gift_address),
            E_TEST_FAILURE
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
            create_gift_internal(
                &creator,
                2,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );
        let gift_address = object::object_address(&gift);

        // Snatch one of the envelopes
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to the expiration.
        timestamp::update_global_time_for_test_secs(25);

        // Reclaim the gift. See that anyone can do it.
        reclaim_gift<CurrentTimeMicroseconds>(&snatcher1, gift);

        // See that the gift is deleted.
        assert!(
            !object::object_exists<Gift>(gift_address),
            E_TEST_FAILURE
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
    #[expected_failure(abort_code = 196620, location = Self)]
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
            create_gift_internal(
                &creator,
                2,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch only one of the envelopes.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that reclaiming the gift fails if you're not the owner.
        reclaim_gift<CurrentTimeMicroseconds>(&snatcher1, gift);
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
            create_gift_internal(
                &creator,
                2,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch only one of the envelopes.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that reclaiming the gift fails before the expiration with `reclaim_gift`
        // if you're not the owner.
        reclaim_gift<CurrentTimeMicroseconds>(&snatcher1, gift);
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
            create_gift_internal(
                &creator,
                2,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch only one of the envelopes.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );

        // Fast forward time to before the expiration.
        timestamp::update_global_time_for_test_secs(24);

        // See that you can reclaim the gift at any time if you're the owner.
        reclaim_gift<CurrentTimeMicroseconds>(&creator, gift);
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
        create_gift_internal(
            &creator,
            0,
            25,
            fa,
            option::none(),
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
        create_gift_internal(
            &creator,
            5,
            too_far_expiration,
            fa,
            option::none(),
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

        create_gift_internal(
            &creator,
            5,
            25,
            fa,
            option::none(),
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
            create_gift_internal(
                &creator,
                5,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::some(verification_key),
                false
            );

        // This should fail because the empty vector is not a valid signed message.
        let signed_message = vector::empty<u8>();
        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                5,
                25,
                fa,
                option::none(),
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

        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                5,
                25,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                true
            );

        // This should fail because the empty vector is not a valid public key.
        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                5,
                100,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        // Snatch as snatcher 1 and assert their balance has increased.
        snatch_envelope<CurrentTimeMicroseconds>(
            &snatcher1,
            gift,
            vector::empty(),
            vector::empty()
        );
        assert!(
            coin::balance<AptosCoin>(snatcher1_address) > DEFAULT_STARTING_BALANCE, 0
        );

        // Snatch as snatcher 2 and assert their balance has increased.
        snatch_envelope<CurrentTimeMicroseconds>(
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
            create_gift_internal(
                &creator,
                5,
                100,
                fa,
                option::none(),
                string::utf8(b"hey friends"),
                option::none(),
                false
            );

        set_paused(&deployer, true);
        assert!(paused() == true, 0);

        // Snatch as snatcher 1 and assert their balance has increased.
        snatch_envelope<CurrentTimeMicroseconds>(
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
