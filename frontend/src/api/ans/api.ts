// Whenever showing an account address, call this function to try and get an ANS
// name for it first. If one isn't found, just return the account address.
export async function getAccountAddressPretty(
  accountAddress: string
): Promise<string> {
  const response = await fetch(
    `https://www.aptosnames.com/api/testnet/v1/name/${accountAddress}`
  );
  const json = await response.json();
  if (json["name"] !== undefined) {
    return json["name"];
  } else {
    return accountAddress;
  }
}
