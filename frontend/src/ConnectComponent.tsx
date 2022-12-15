import { Button } from "@chakra-ui/react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";

export const ConnectComponent = () => {
  const { connect, wallets } = useWallet();

  // Only Petra right now.
  const handleConnectWallet = () => {
    console.log(`Wallets: ${JSON.stringify(wallets)}`);
    let wallet = wallets.find((w) => w.name === "Petra");
    if (!wallet) {
      console.log("No Petra wallet found");
      return;
    }
    console.log(`Connecting to ${wallet.name}...`);
    connect(wallet.name);
  };

  return (
    <Button
      onClick={() => {
        handleConnectWallet();
      }}
    >
      Connect Wallet
    </Button>
  );
};
