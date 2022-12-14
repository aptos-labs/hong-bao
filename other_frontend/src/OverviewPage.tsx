import * as React from "react"
import {
  Button,
  Text,
} from "@chakra-ui/react"
import { useWallet } from "@aptos-labs/wallet-adapter-react";

export const ChatOverviewPage = () => {
  const {
    connect,
    account,
    network,
    connected,
    disconnect,
    wallet,
    wallets,
    signAndSubmitTransaction,
    signTransaction,
    signMessage,
  } = useWallet();

  return (
    <Text>hey</Text>
  );
}
