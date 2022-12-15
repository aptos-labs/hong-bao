import * as React from "react";
import { Button } from "@chakra-ui/react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";

export const DisconnectComponent = () => {
  const { disconnect } = useWallet();

  const handleDisconnectWallet = () => {
    disconnect();
  };

  return (
    <Button
      onClick={() => {
        handleDisconnectWallet();
      }}
    >
      Disconnect
    </Button>
  );
};
