import * as React from "react"
import {
  ChakraProvider,
  Box,
  Text,
  Link,
  VStack,
  Code,
  Grid,
  theme,
  Button,
} from "@chakra-ui/react"
import { ColorModeSwitcher } from "./ColorModeSwitcher"
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { ConnectComponent } from "./ConnectComponent";
import { DisconnectComponent } from "./DisconnectComponent";

export const App = () => {
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

  // Only Petra right now.
  const handleConnectWallet = () => {
    console.log(`Wallets: ${JSON.stringify(wallets)}`);
    let petra = wallets.find((w) => w.name === "Petra");
    if (!petra) {
      console.log("No Petra wallet found");
      return;
    }
    console.log(`Connecting to ${wallet}...`);
    connect(petra.name);
  };

  let inner;
  if (!connected) {
    inner = (
      <Box textAlign="center" fontSize="xl">
        <Grid minH="100vh" p={3}>
          <ColorModeSwitcher justifySelf="flex-end" />
          <VStack spacing={8}>
            <Text>
              Aptos Hong Bao 🧧
            </Text>
            <ConnectComponent />
          </VStack>
        </Grid>
      </Box>
    );
  } else {
    inner = (
      <Box textAlign="center" fontSize="xl">
        <Grid minH="100vh" p={3}>
          <ColorModeSwitcher justifySelf="flex-end" />
          <VStack spacing={8}>
            <Text>
              Aptos Hong Bao 🧧
            </Text>
            <Text>
              Connected to {wallet!.name}
            </Text>
            <DisconnectComponent />
          </VStack>
        </Grid>
      </Box>
    );
  }

  return (
    <ChakraProvider theme={theme}>
      {inner}
    </ChakraProvider>
  );
}
