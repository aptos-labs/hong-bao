import { request, gql } from "graphql-request";
import { removeDuplicates } from "../../helpers";
import { ChatRoom } from "../types";

const indexerUrl =
  "https://indexer-testnet.staging.gcp.aptosdev.com/v1/graphql";

const tokensOwnedByAccountQueryDoc = gql`
  query TokensOwnedByAccount($owner_address: String, $offset: Int) {
    current_token_ownerships(
      where: {
        owner_address: { _eq: $owner_address }
        amount: { _gt: "0" }
        table_type: { _eq: "0x3::token::TokenStore" }
      }
      order_by: { last_transaction_version: desc }
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
  const variables = { owner_address: userAccountAddress, offset: 0 };
  return await request({
    url: indexerUrl,
    document: tokensOwnedByAccountQueryDoc,
    variables,
  });
}

export async function getChatRoomsUserIsIn(
  userAccountAddress: string
): Promise<ChatRoom[]> {
  const tokens = await fetchTokensOwnedByAccount(userAccountAddress);
  return removeDuplicates(tokens["current_token_ownerships"]);
}

const accountsWhoOwnTokenQueryDoc = gql`
  query AccountsWhoOwnToken(
    $creator_address: String
    $collection_name: String
    $offset: Int
  ) {
    current_token_ownerships(
      where: {
        creator_address: { _eq: $creator_address }
        collection_name: { _eq: $collection_name }
        amount: { _gt: "0" }
        table_type: { _eq: "0x3::token::TokenStore" }
      }
      order_by: { last_transaction_version: desc }
      offset: $offset
    ) {
      owner_address
    }
  }
`;

// creatorAddress must be a 0x account address.
async function fetchAccountsWhoOwnToken(
  creatorAddress: string,
  collectionName: string
) {
  // TODO: Do pagination.
  const variables = {
    creator_address: creatorAddress,
    collection_name: collectionName,
    offset: 0,
  };
  return await request({
    url: indexerUrl,
    document: accountsWhoOwnTokenQueryDoc,
    variables,
  });
}

export async function getAccountsInChatRoom(
  creatorAddress: string,
  collectionName: string
): Promise<string[]> {
  const tokens = await fetchAccountsWhoOwnToken(creatorAddress, collectionName);
  return removeDuplicates(
    tokens["current_token_ownerships"].map((v: any) => v.owner_address)
  );
}
