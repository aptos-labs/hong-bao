import { moduleAddress, moduleName } from "./constants";
import { AptosClient } from "aptos";

/// Send a transaction through the wallet to send a gift to the chat room.
export async function sendGift(
  signAndSubmitTransaction: (txn: any) => Promise<any>,
  // Collection creator address + collection name.
  currentChatRoomKey: string,
  // The addresses of the recipients.
  allowedRecipients: string[],
  numberOfPackets: number,
  // Amount in OCTA, not APT.
  giftAmount: number,
  expirationUnixtimeSecs: number
) {
  const transaction = {
    type: "entry_function_payload",
    function: `${moduleAddress}::${moduleName}::create_gift`,
    type_arguments: [],
    arguments: [
      currentChatRoomKey,
      allowedRecipients,
      numberOfPackets,
      giftAmount,
      expirationUnixtimeSecs,
    ],
  };

  const pendingTransaction = await signAndSubmitTransaction(transaction);

  const client = new AptosClient("https://fullnode.testnet.aptoslabs.com");
  await client.waitForTransactionWithResult(pendingTransaction.hash, {
    checkSuccess: true,
  });
}
