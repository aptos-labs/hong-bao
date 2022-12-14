const indexerUrl = "https://indexer-testnet.staging.gcp.aptosdev.com/v1/graphql";

async function fetchGraphQL(
    indexerUrl: string,
    query: string,
    operationName: string,
    variables: Record<string, any>
) {
    return fetch(indexerUrl, {
        method: 'POST',
        body: JSON.stringify({
            query,
            variables,
            operationName,
        }),
    });
}

const queryDoc = `
    query TokensOwnedByAccount($owner_address: String, $offset: Int) {
      current_token_ownerships(
        where: {owner_address: {_eq: $owner_address}, amount: {_gt: "0"}, table_type: {_eq: "0x3::token::TokenStore"}}
        order_by: {last_transaction_version: desc}
        offset: $offset
      ) {
        creator_address
        collection_name
      }
    }
`;

// userAccountAddress must be a 0x account address.
export function fetchTokensOwnedByAccount(userAccountAddress: string) {
    // TODO: Do pagination.
    return fetchGraphQL(indexerUrl, queryDoc, "TokensOwnedByAccount", { "owner_address": userAccountAddress, "offset": 0 })
}
