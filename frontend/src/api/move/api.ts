import { moduleAddress, moduleName } from "./constants";
import { AptosClient } from "aptos";

const fullnode = "https://fullnode.testnet.aptoslabs.com";

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
  console.log("transaction", JSON.stringify(transaction));

  const pendingTransaction = await signAndSubmitTransaction(transaction);

  const client = new AptosClient(fullnode);
  await client.waitForTransactionWithResult(pendingTransaction.hash, {
    checkSuccess: true,
  });
}

export type GiftInfo = {
  // Whether the account is offering a gift to this chat.
  offering: boolean;

  // When the gift expires.
  expirationTimeSecs: number;

  // The remaining balance of the gift.
  remainingBalance?: number;

  // The number of packets in the gift.
  remainingPackets?: number;

  // Folks who are still allowed to claim packets from the gift.
  allowedRecipients?: string[];
};

/// Check whether the account in question is offering a gift to this chat.
export async function checkForGift(
  // Collection creator address + collection name.
  currentChatRoomKey: string,
  // The address of the account to check.
  accountAddress: string
): Promise<GiftInfo> {
  const client = new AptosClient(fullnode);

  let out: GiftInfo = {
    offering: false,
    expirationTimeSecs: 0,
  };
  try {
    const resource = await client.getAccountResource(
      accountAddress,
      `${moduleAddress}::${moduleName}::GiftHolder`
    );
    for (const gift of (resource.data as any).gifts.data) {
      console.log("gift", gift);
      if (gift.key === currentChatRoomKey) {
        out.offering = true;
        out.expirationTimeSecs = gift.value.expiration_time;
        out.remainingBalance = parseInt(gift.value.remaining_balance.value);
        out.remainingPackets = parseInt(gift.value.remaining_packets);
        out.allowedRecipients = gift.value.allowed_recipients.data.map(
          (v: any) => v.key
        );
        break;
      }
    }
  } catch (_e) {}

  return out;
}

/// Send a transaction through the wallet to snatch a packet to the chat room.
export async function snatchPacket(
  signAndSubmitTransaction: (txn: any) => Promise<any>,
  // Address of the gifter.
  gifterAddress: string,
  // Collection creator address + collection name.
  currentChatRoomKey: string
) {
  const transaction = {
    type: "entry_function_payload",
    function: `${moduleAddress}::${moduleName}::snatch_packet`,
    type_arguments: [],
    arguments: [gifterAddress, currentChatRoomKey],
  };

  const pendingTransaction = await signAndSubmitTransaction(transaction);

  const client = new AptosClient(fullnode);
  await client.waitForTransactionWithResult(pendingTransaction.hash, {
    checkSuccess: true,
  });
}

/// Create a new chat room (NFT collection), mint tokens in it, and offer those tokens to people.
export async function createChatRoom(
  signAndSubmitTransaction: (txn: any) => Promise<any>,
  // New chat room name (collection name).
  newChatRoomName: string,
  // Addresses of people to invite (mint tokens and offer them).
  addressesToInvite: string[]
) {
  const transaction = {
    type: "entry_function_payload",
    function: `${moduleAddress}::${moduleName}::create_chat_room`,
    type_arguments: [],
    arguments: [newChatRoomName, addressesToInvite],
  };

  const pendingTransaction = await signAndSubmitTransaction(transaction);

  const client = new AptosClient(fullnode);
  await client.waitForTransactionWithResult(pendingTransaction.hash, {
    checkSuccess: true,
  });
}
