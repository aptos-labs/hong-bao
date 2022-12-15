import { Box, Typography } from "@material-ui/core";
import React, { HTMLAttributes, useEffect, useState, useContext } from "react";
import { ChatStateContext } from "../ChatSection";
import {
  getShortAddress,
  getExpirationTimePretty,
  niceRed,
  niceGold,
} from "../helpers";
import { UserData } from "../user/types";
import UserAvatar from "../user/UserAvatar";
import { checkForGift, GiftInfo, snatchPacket } from "../api/move/api";
import { grey } from "@material-ui/core/colors";
import {
  Button,
  Modal,
  Link,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalFooter,
  ModalBody,
  ModalCloseButton,
  useDisclosure,
  Spinner,
  useToast,
} from "@chakra-ui/react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";

type UserProps = {
  user: UserData;
} & HTMLAttributes<HTMLDivElement>;

type GiftData = {
  giftInfo: GiftInfo;
  // If the User we're working with here is the actual user, not someone else,
  // this should be true.
  userIsSelf: boolean;
};

const User: React.FC<UserProps> = ({ className, user }: UserProps) => {
  const chatStateContext = useContext(ChatStateContext);

  const [giftData, updateGiftData] = useState<GiftData>({
    giftInfo: { offering: false, expirationTimeSecs: 0 },
    userIsSelf: `0x${user.address}` === chatStateContext.user.address,
  });

  const { isOpen, onOpen, onClose } = useDisclosure();
  const { signAndSubmitTransaction } = useWallet();
  const toast = useToast();

  const [snatchingPacket, updateSnatchingPacket] = useState<boolean>(false);

  useEffect(() => {
    const checkForGiftsWrapper = async () => {
      console.log("Checking for gifts" + user.address);
      const giftInfo = await checkForGift(
        chatStateContext.currentChatRoomKey,
        user.address
      );
      updateGiftData((prevGiftData) => ({
        ...prevGiftData,
        giftInfo,
      }));
    };

    // Call it once on mount.
    checkForGiftsWrapper();

    // Set a timer to keep calling it.
    setInterval(() => {
      checkForGiftsWrapper();
    }, 10000);
  }, []);

  const handleSnatchPacket = () => {
    const snatchPacketWrapper = async () => {
      updateSnatchingPacket(true);

      try {
        await snatchPacket(
          signAndSubmitTransaction,
          user.address,
          chatStateContext.currentChatRoomKey
        );
        // If we get here, the transaction was committed successfully on chain.
        toast({
          title: "Successfully snatched!",
          description: "Successfully snatched a packet, check your wallet!",
          status: "success",
          duration: 5000,
          isClosable: true,
        });
      } catch (e) {
        toast({
          title: "Failed to snatch a packet.",
          description: "Error: " + e,
          status: "error",
          duration: 7000,
          isClosable: true,
        });
      }

      onClose();
      updateSnatchingPacket(false);
    };

    snatchPacketWrapper();
  };

  const squareSize = 35;
  let nameComponent;
  if (giftData.giftInfo.offering) {
    if (giftData.userIsSelf) {
      // TODO: Have a modal showing info about the gift.
      nameComponent = <Link onClick={onOpen}>Your Gift</Link>;
    } else if (giftData.giftInfo.expirationTimeSecs < Date.now() / 1000) {
      nameComponent = (
        <Button
          onClick={onOpen}
          width={squareSize}
          height={squareSize}
          bg={grey[300]}
          mr={1}
        />
      );
    } else {
      nameComponent = (
        <Button
          onClick={onOpen}
          width={squareSize}
          height={squareSize}
          bg={niceRed}
          mr={1}
        />
      );
    }
  } else {
    nameComponent = (
      <Typography variant="body1">{getShortAddress(user.address)}</Typography>
    );
  }

  const buildModal = (giftData: GiftData) => {
    let body;
    let button = <Button onClick={onClose}>Ok</Button>;
    console.log("allowed recipients: ", giftData.giftInfo.allowedRecipients);
    console.log("user address: ", user.address);
    if (giftData.userIsSelf) {
      body = (
        <>
          <Box>{`Amount Remaining: ${
            giftData.giftInfo.remainingBalance! / 100_000_000
          } APT`}</Box>
          <Box>{`Packets Remaining: ${giftData.giftInfo.remainingPackets}`}</Box>
          <Box>{`Expires: ${getExpirationTimePretty(
            giftData.giftInfo.expirationTimeSecs
          )}`}</Box>
        </>
      );
    } else {
      if (giftData.giftInfo.expirationTimeSecs < Date.now() / 1000) {
        body = (
          <>
            <Box>Gift has expired 😭</Box>
          </>
        );
      } else if (
        !giftData.giftInfo.allowedRecipients!.includes(
          chatStateContext.user.address
        )
      ) {
        body = (
          <>
            <Box>You've already snatched a packet from this gift!</Box>
          </>
        );
      } else if (giftData.giftInfo.remainingPackets! > 0) {
        body = (
          <>
            <Box>
              {giftData.giftInfo.remainingPackets!} packets left, snatch one
              quick!
            </Box>
          </>
        );
        button = (
          <Button
            onClick={() => handleSnatchPacket()}
            mr={3}
            bg={niceRed}
            style={{ color: niceGold }}
          >
            {snatchingPacket ? <Spinner /> : "Snatch!"}
          </Button>
        );
      }
    }
    return (
      <Modal isOpen={isOpen} onClose={onClose}>
        <ModalOverlay />
        <ModalContent>
          <ModalHeader>Your Gift 🧧</ModalHeader>
          <ModalCloseButton />
          <ModalBody>{body}</ModalBody>
          <ModalFooter>{button}</ModalFooter>
        </ModalContent>
      </Modal>
    );
  };

  // TODO: Add a button to reclaim a gift you've sent that has expired.
  return (
    <>
      <Box className={className} display="flex" p={1}>
        <Box mr={1}>
          <UserAvatar user={user} />
        </Box>
        <Box alignSelf="center">{nameComponent}</Box>
      </Box>
      {buildModal(giftData)}
    </>
  );
};

export default User;
