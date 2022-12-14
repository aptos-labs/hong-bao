import { request, gql } from 'graphql-request'
import { removeDuplicates } from '../../helpers';
import { ChatRoom } from '../types';

const indexerUrl = "https://indexer-testnet.staging.gcp.aptosdev.com/v1/graphql";

const queryDoc = gql`
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
async function fetchTokensOwnedByAccount(userAccountAddress: string) {
    // TODO: Do pagination.
    const variables = { "owner_address": userAccountAddress, "offset": 0 };
    console.log(`variables: ${JSON.stringify(variables)}`);
    return await request({
        url: indexerUrl,
        document: queryDoc,
        variables,
      });
}

export async function getChatRoomsUserIsIn(userAccountAddress: string): Promise<ChatRoom[]> {
    const tokens = await fetchTokensOwnedByAccount(userAccountAddress);
    return removeDuplicates(tokens["current_token_ownerships"]);
}
