import { Command, Option } from "clipanion";
import { BaseCommand } from "../command";
import { getUsageCategoryFromPaths } from "../helpers";
import {
  Account,
  AccountAddress,
  Aptos,
  AptosConfig,
  Ed25519PrivateKey,
  Network,
} from "@aptos-labs/ts-sdk";
import { createEntryPayload } from "@thalalabs/surf";
import * as fs from "fs";
import * as path from "path";
import { HONG_BAO_MODULE_ABI } from "../move/abis";

export class ExpiredCommand extends BaseCommand {
  static paths = [["reclaim", "expired"]];

  static usage = Command.Usage({
    category: getUsageCategoryFromPaths(this.paths),
    description: `Reclaim expired gifts (or gifts with zero envelopes left)`,
    examples: [
      [
        `Reclaim expired gifts`,
        `$0 reclaim expired --indexer-api-url https://api.testnet.aptoslabs.com/nocode/v1/api/cm6d0zcxl0007s6013nmo8bm1/v1/graphql --indexer-api-key aptoslabs_key_blah --contract-address 0x123 --private-key 0x321`,
      ],
    ],
  });

  // Options
  indexerApiUrl = Option.String("--indexer-api-url", { required: true });
  indexerApiKey = Option.String("--indexer-api-key", { required: true });

  contractAddress = Option.String("--contract-address", { required: true });

  dryRun = Option.Boolean("--dry-run");

  privateKey = Option.String("--private-key", { required: false });
  privateKeyFile = Option.String("--private-key-file", { required: false });

  /**
   * Our parameterized GraphQL query for gifts, supporting pagination.
   */
  private static GET_GIFTS_QUERY = `
    query MyQuery($limit: Int!, $offset: Int!) {
      gifts(where: {}, limit: $limit, offset: $offset) {
        gift_address
        num_remaining_envelopes
        expiration_time
        coin_type
        is_reclaimed
      }
    }
  `;

  /**
   * Calls our GraphQL endpoint with the provided query, operation name, and variables.
   */
  private async fetchGraphQL(
    operationsDoc: string,
    operationName: string,
    variables: Record<string, any>,
  ): Promise<any> {
    const response = await fetch(this.indexerApiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.indexerApiKey}`,
      },
      body: JSON.stringify({
        query: operationsDoc,
        variables,
        operationName,
      }),
    });

    return response.json();
  }

  /**
   * Fetch a single "page" of gifts (using limit and offset).
   */
  private async fetchGifts(limit: number, offset: number): Promise<Gift[]> {
    const { data, errors } = await this.fetchGraphQL(
      ExpiredCommand.GET_GIFTS_QUERY,
      "MyQuery",
      { limit, offset },
    );

    if (errors) {
      this.context.stderr.write(`GraphQL Errors: ${JSON.stringify(errors)}\n`);
      return [];
    }

    return data?.gifts ?? [];
  }

  /**
   * Fetches *all* gifts by calling `fetchGifts` repeatedly until no more remain.
   */
  private async fetchAllGifts(limit = 99): Promise<Gift[]> {
    let offset = 0;
    const allGifts: Gift[] = [];

    while (true) {
      const gifts = await this.fetchGifts(limit, offset);
      allGifts.push(...gifts);

      if (gifts.length < limit) {
        break;
      }
      offset += limit;
    }

    return allGifts;
  }

  /**
   * Actually call the reclaim function.
   */
  private async reclaimGift(
    aptos: Aptos,
    account: Account,
    giftAddress: string,
    coinType: string,
  ): Promise<void> {
    // Replace with your real implementation
    console.log(
      `Calling reclaim_gift() for gift address: ${giftAddress}\n`,
    );
    // We use a dummy type if the coin type is empty. It means the gift was created
    // by calling `create_gift_fa`.
    const coinTypeGenericTypeParam =
      coinType === "" ? "0x1::timestamp::CurrentTimeMicroseconds" : coinType;
    const payload = createEntryPayload(HONG_BAO_MODULE_ABI, {
      function: "reclaim_gift",
      functionArguments: [giftAddress as `0x${string}`],
      typeArguments: [coinTypeGenericTypeParam],
      address: AccountAddress.from(this.contractAddress).toStringLong(),
    });
    const transaction = await aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: payload,
    });
    const result = await aptos.signAndSubmitTransaction({
      signer: account,
      transaction,
    });
    const transactionHash = result.hash;
    console.log(`Waiting for txn ${transactionHash}...`);
    const executedTransaction = await aptos.waitForTransaction({
      transactionHash,
    });
    console.log(
      `Transaction ${transactionHash} finished with status: ${executedTransaction.vm_status}`,
    );
  }

  /**
   * Main entry point for the command when the user runs it.
   * 1. Optionally loads config or private key as needed.
   * 2. Paginates through GraphQL to get all gifts.
   * 3. Filters to get only expired or zero-envelopes-left gifts.
   * 4. Calls `blah()` on each matching gift.
   */
  async executeInner(): Promise<number> {
    try {
      // Read the private key.
      let privateKeyRaw: string;
      if (this.privateKey) {
        privateKeyRaw = this.privateKey;
      } else if (this.privateKeyFile) {
        const keyPath = path.resolve(process.cwd(), this.privateKeyFile);
        privateKeyRaw = fs.readFileSync(keyPath, "utf8").trim();
      } else {
        throw new Error(
          "No private key provided, use --private-key or --private-key-file",
        );
      }

      const privateKey = new Ed25519PrivateKey(privateKeyRaw);

      // 0. Build the Aptos client.
      const network = this.indexerApiUrl.includes("mainnet")
        ? Network.MAINNET
        : Network.TESTNET;
      const config = new AptosConfig({ network });
      const aptos = new Aptos(config);
      const account = await Account.fromPrivateKey({ privateKey });

      // 1. Fetch all gifts from the GraphQL endpoint.
      const allGifts = await this.fetchAllGifts();

      // 2. Get current time in UNIX seconds
      const nowInSeconds = Math.floor(Date.now() / 1000);

      // 3. Filter out gifts that have expired or have zero envelopes left
      const giftsToReclaim = allGifts.filter((gift) => {
        if (gift.is_reclaimed) {
          return false;
        }
        return (
          nowInSeconds >= gift.expiration_time ||
          gift.num_remaining_envelopes === 0
        );
      });

      // 4. For each filtered gift, call `blah()`.
      for (const gift of giftsToReclaim) {
        if (this.dryRun) {
          console.log(
            `Would reclaim gift ${gift.gift_address} with coin type ${gift.coin_type}`,
          );
        } else {
          await this.reclaimGift(
            aptos,
            account,
            gift.gift_address,
            gift.coin_type,
          );
        }
      }

      console.log("\n");

      // If nothing goes wrong, return success exit code:
      console.log(
        `Checked a total of ${allGifts.length} gifts. ${giftsToReclaim.length} were ready to be reclaimed.\n`,
      );
      return 0;
    } catch (error) {
      this.context.stderr.write(`Error reclaiming expired gifts: ${error}\n`);
      return 1;
    }
  }
}

/**
 * Define the shape of the data we expect back from the GraphQL query.
 */
type Gift = {
  gift_address: string;
  num_remaining_envelopes: number;
  expiration_time: number;
  coin_type: string;
  is_reclaimed: boolean;
};
