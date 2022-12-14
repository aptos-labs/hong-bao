use anyhow::Result;
use aptos_sdk::types::account_address::AccountAddress;
use graphql_client::{GraphQLQuery, Response};
use reqwest::{Client as ReqwestClient, Url};

#[derive(Debug)]
pub struct IndexerClient {
    // The URL of the indexer endpoint.
    pub url: Url,

    // The reqwest client.
    pub client: ReqwestClient,
}

impl IndexerClient {
    pub fn new(url: Url) -> Self {
        IndexerClient {
            url,
            client: ReqwestClient::new(),
        }
    }

    pub async fn get_tokens_on_account(
        &self,
        account_address: &AccountAddress,
    ) -> Result<tokens_owned_by_account::ResponseData> {
        // TODO: Do pagination.
        let variables: tokens_owned_by_account::Variables = tokens_owned_by_account::Variables {
            owner_address: Some(account_address.to_hex_literal()),
            offset: Some(0),
        };
        let request_body = TokensOwnedByAccount::build_query(variables);
        let res = self
            .client
            .post(self.url.clone())
            .json(&request_body)
            .send()
            .await?;
        let response: Response<tokens_owned_by_account::ResponseData> = res.json().await?;
        if let Some(errors) = response.errors {
            return Err(anyhow::anyhow!(
                "Errors fetching tokens on account: {:?}",
                errors
            ));
        }
        match response.data {
            Some(data) => Ok(data),
            None => Err(anyhow::anyhow!(
                "No data returned from indexer when fetching tokens on account"
            )),
        }
    }
}

// Note: It is important that the name here and the name of the query in the query
// file match, since we're putting multiple queries in the same file.
#[derive(GraphQLQuery)]
#[graphql(
    schema_path = "assets/indexer_schema.graphql",
    query_path = "assets/indexer_queries.graphql",
    response_derives = "Debug",
    variables_derives = "Debug"
)]
struct TokensOwnedByAccount;

#[cfg(test)]
mod test {
    use super::*;
    use std::str::FromStr;

    #[tokio::test]
    async fn test_get_tokens_on_account() {
        let account_address = AccountAddress::from_str(
            "0xb078d693856a65401d492f99ca0d6a29a0c5c0e371bc2521570a86e40d95f823",
        )
        .unwrap();
        let indexer_client = IndexerClient::new(
            Url::parse("https://indexer-testnet.staging.gcp.aptosdev.com/v1/graphql").unwrap(),
        );
        let response = indexer_client
            .get_tokens_on_account(&account_address)
            .await
            .unwrap();
        println!("{:#?}", response);
    }
}
