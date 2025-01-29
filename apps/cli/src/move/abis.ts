// See the README for an explanation of where these came from. Don't rely on the module
// address or name, we publish essentially identical modules under different addresses
// and names.

export const HONG_BAO_MODULE_ABI = {
  address: "0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5",
  name: "hongbao",
  friends: [],
  exposed_functions: [
    {
      name: "create_gift",
      visibility: "public",
      is_entry: false,
      is_view: false,
      generic_type_params: [],
      params: [
        "&signer",
        "u64",
        "u64",
        "0x1::fungible_asset::FungibleAsset",
        "0x1::option::Option<0x1::string::String>",
        "0x1::string::String",
        "0x1::option::Option<vector<u8>>",
        "bool",
      ],
      return: [
        "0x1::object::Object<0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5::hongbao::Gift>",
      ],
    },
    {
      name: "create_gift_coin",
      visibility: "public",
      is_entry: true,
      is_view: false,
      generic_type_params: [
        {
          constraints: [],
        },
      ],
      params: [
        "&signer",
        "u64",
        "u64",
        "u64",
        "0x1::string::String",
        "0x1::option::Option<vector<u8>>",
        "bool",
      ],
      return: [],
    },
    {
      name: "create_gift_fa",
      visibility: "public",
      is_entry: true,
      is_view: false,
      generic_type_params: [],
      params: [
        "&signer",
        "u64",
        "u64",
        "u64",
        "0x1::object::Object<0x1::fungible_asset::Metadata>",
        "0x1::string::String",
        "0x1::option::Option<vector<u8>>",
        "bool",
      ],
      return: [],
    },
    {
      name: "paused",
      visibility: "public",
      is_entry: false,
      is_view: true,
      generic_type_params: [],
      params: [],
      return: ["bool"],
    },
    {
      name: "reclaim_gift",
      visibility: "public",
      is_entry: true,
      is_view: false,
      generic_type_params: [
        {
          constraints: [],
        },
      ],
      params: [
        "&signer",
        "0x1::object::Object<0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5::hongbao::Gift>",
      ],
      return: [],
    },
    {
      name: "set_paused",
      visibility: "public",
      is_entry: true,
      is_view: false,
      generic_type_params: [],
      params: ["&signer", "bool"],
      return: [],
    },
    {
      name: "snatch_envelope",
      visibility: "private",
      is_entry: true,
      is_view: false,
      generic_type_params: [
        {
          constraints: [],
        },
      ],
      params: [
        "&signer",
        "0x1::object::Object<0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5::hongbao::Gift>",
        "vector<u8>",
        "vector<u8>",
      ],
      return: [],
    },
  ],
  structs: [
    {
      name: "ClaimEnvelopeEvent",
      is_native: false,
      is_event: true,
      abilities: ["drop", "store"],
      generic_type_params: [],
      fields: [
        {
          name: "gift_address",
          type: "address",
        },
        {
          name: "recipient",
          type: "address",
        },
        {
          name: "fa_metadata_address",
          type: "address",
        },
        {
          name: "coin_type",
          type: "0x1::string::String",
        },
        {
          name: "snatched_amount",
          type: "u64",
        },
        {
          name: "remaining_envelopes",
          type: "0x1::aggregator_v2::AggregatorSnapshot<u64>",
        },
        {
          name: "remaining_amount",
          type: "0x1::aggregator_v2::AggregatorSnapshot<u64>",
        },
      ],
    },
    {
      name: "Config",
      is_native: false,
      is_event: false,
      abilities: ["key"],
      generic_type_params: [],
      fields: [
        {
          name: "paused",
          type: "bool",
        },
      ],
    },
    {
      name: "CreateGiftEvent",
      is_native: false,
      is_event: true,
      abilities: ["drop", "store"],
      generic_type_params: [],
      fields: [
        {
          name: "gift_address",
          type: "address",
        },
        {
          name: "creator",
          type: "address",
        },
        {
          name: "num_envelopes",
          type: "u64",
        },
        {
          name: "expiration_time",
          type: "u64",
        },
        {
          name: "fa_metadata_address",
          type: "address",
        },
        {
          name: "coin_type",
          type: "0x1::string::String",
        },
        {
          name: "amount",
          type: "u64",
        },
        {
          name: "message",
          type: "0x1::string::String",
        },
        {
          name: "is_reclaimed",
          type: "bool",
        },
        {
          name: "reclaimed_amount",
          type: "u64",
        },
      ],
    },
    {
      name: "Gift",
      is_native: false,
      is_event: false,
      abilities: ["store", "key"],
      generic_type_params: [],
      fields: [
        {
          name: "recipients",
          type: "0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5::hongbao::Recipients",
        },
        {
          name: "num_envelopes",
          type: "u64",
        },
        {
          name: "num_envelopes_remaining",
          type: "0x1::aggregator_v2::Aggregator<u64>",
        },
        {
          name: "coins_remaining",
          type: "0x1::aggregator_v2::Aggregator<u64>",
        },
        {
          name: "expiration_time",
          type: "u64",
        },
        {
          name: "fa_metadata",
          type: "0x1::object::Object<0x1::fungible_asset::Metadata>",
        },
        {
          name: "original_asset_was_coin",
          type: "bool",
        },
        {
          name: "message",
          type: "0x1::string::String",
        },
        {
          name: "paylink_verification_key",
          type: "0x1::option::Option<vector<u8>>",
        },
        {
          name: "keyless_only",
          type: "bool",
        },
        {
          name: "parallel_buckets",
          type: "0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5::parallel_buckets::ParallelBuckets<u64>",
        },
        {
          name: "extend_ref",
          type: "0x1::object::ExtendRef",
        },
        {
          name: "transfer_ref",
          type: "0x1::object::TransferRef",
        },
        {
          name: "delete_ref",
          type: "0x1::object::DeleteRef",
        },
      ],
    },
    {
      name: "Recipients",
      is_native: false,
      is_event: false,
      abilities: ["store"],
      generic_type_params: [],
      fields: [],
    },
    {
      name: "ReclaimGiftEvent",
      is_native: false,
      is_event: true,
      abilities: ["drop", "store"],
      generic_type_params: [],
      fields: [
        {
          name: "gift_address",
          type: "address",
        },
        {
          name: "creator",
          type: "address",
        },
        {
          name: "reclaimed_amount",
          type: "u64",
        },
        {
          name: "is_reclaimed",
          type: "bool",
        },
      ],
    },
  ],
} as const;
