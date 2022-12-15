import { Box, createStyles, TextField, Theme } from "@material-ui/core";
import { makeStyles } from "@material-ui/core/styles";
import React, { ChangeEvent, FormEvent, useContext, useState } from "react";
import { SendJsonMessage } from "react-use-websocket/dist/lib/types";
import apiProto from "../api/chat/proto";
import {
  Box as ChakraBox,
  Button,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalFooter,
  ModalBody,
  ModalCloseButton,
  useDisclosure,
  FormLabel,
  FormControl,
  NumberInput,
  NumberInputField,
  Spinner,
  useToast,
} from "@chakra-ui/react";
import { ChatStateContext } from "../ChatSection";
import { sendGift } from "../api/move/api";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { niceGold, niceRed } from "../helpers";
import { getAccountsInChatRoom } from "../api/indexer/api";

const useStyles = makeStyles((theme: Theme) =>
  createStyles({
    messageInput: {
      marginLeft: theme.spacing(2),
      flexGrow: 1,
    },
    postButton: {
      marginLeft: theme.spacing(2),
    },
  })
);

type PostFieldProps = {
  currentChatRoomKey: string;
};

type PostFieldState = {
  body: string;
  bodyValid: boolean;
};

const PostField: React.FC<PostFieldProps> = ({
  currentChatRoomKey,
}: PostFieldProps) => {
  const classes = useStyles();
  const [state, setState] = useState<PostFieldState>({
    body: "",
    bodyValid: false,
  });

  const chatStateContext = useContext(ChatStateContext);

  const { isOpen, onOpen, onClose } = useDisclosure();

  const toast = useToast();

  /*
    const postErrorCode = useSelector((state: AppState) => state.feed.postError);
    let postError = null;
    if (state.body.trim().length !== 0) {
        switch (postErrorCode) {
            case OutputError.NotJoined:
                postError = 'Not joined.';
                break;
            case OutputError.InvalidMessageBody:
                postError = 'Invalid message.';
                break;
        }
    }
  */

  const { signAndSubmitTransaction } = useWallet();

  const isBodyValid = (body: string) => body.length > 0 && body.length <= 256;

  const handleBodyChange = (event: ChangeEvent<HTMLInputElement>) => {
    const body = event.target.value;
    setState((prevState) => ({
      ...prevState,
      body,
      bodyValid: isBodyValid(body.trim()),
    }));
  };

  const handlePost = (e: FormEvent, sendJsonMessage: SendJsonMessage) => {
    e.preventDefault();
    const body = state.body.trim();
    if (!isBodyValid(body)) {
      return;
    }
    setState((_prevState) => ({ body: "", bodyValid: false }));
    sendJsonMessage(apiProto.post(body));
  };

  const [giftAmount, updateGiftAmount] = useState<number | undefined>(
    undefined
  );
  const [numberOfPackets, updatenumberOfPackets] = useState<number | undefined>(
    undefined
  );
  const [sendingGift, updateSendingGift] = useState<boolean>(false);

  const handleSendGift = () => {
    const sendGiftWrapper = async () => {
      updateSendingGift(true);

      try {
        // Get the addresses of people with permission to enter the chat room.
        // As in, find those who own this token.
        let addresses = await getAccountsInChatRoom(
          chatStateContext.chatRoom.creator_address,
          chatStateContext.chatRoom.collection_name
        );

        // TODO: Make this configurable.
        const expirationUnixtimeSecs = Math.floor(Date.now() / 1000) + 300; // 5 minutes from now.
        await sendGift(
          signAndSubmitTransaction,
          currentChatRoomKey,
          // Remove our own address.
          addresses.filter(
            (address) => address !== chatStateContext.user.address
          ),
          numberOfPackets!,
          giftAmount! * 100_000_000,
          expirationUnixtimeSecs
        );
        // If we get here, the transaction was committed successfully on chain.
        toast({
          title: "Sent gift!",
          description: "Successfully sent gift of " + giftAmount + " APT!",
          status: "success",
          duration: 5000,
          isClosable: true,
        });
      } catch (e) {
        toast({
          title: "Failed to send gift.",
          description: "Error: " + e,
          status: "error",
          duration: 7000,
          isClosable: true,
        });
      }

      onClose();
      updateSendingGift(false);
    };

    sendGiftWrapper();
  };

  // TODO: Do form validation in the modal properly.
  return (
    <>
      <ChakraBox w={"95%"}>
        <Box
          component="form"
          onSubmit={(e) => handlePost(e, chatStateContext.sendJsonMessage)}
          display="flex"
          justifyContent="center"
          alignItems="baseline"
        >
          <TextField
            className={classes.messageInput}
            label="Say..."
            value={state.body}
            onChange={handleBodyChange}
            error={false}
            helperText={""}
          />
          <Button
            bg="white"
            className={classes.postButton}
            variant="contained"
            color="primary"
            disabled={false}
            onClick={(e) => handlePost(e, chatStateContext.sendJsonMessage)}
          >
            Send
          </Button>
          <Button
            bg="#d12d29"
            style={{ color: "#fdf9aa" }}
            className={classes.postButton}
            variant="contained"
            disabled={false}
            onClick={onOpen}
          >
            Gift
          </Button>
        </Box>
      </ChakraBox>
      <Modal isOpen={isOpen} onClose={onClose}>
        <ModalOverlay />
        <ModalContent>
          <ModalHeader>Send Gift 🧧</ModalHeader>
          <ModalCloseButton />
          <ModalBody>
            <FormControl paddingBottom={5} isRequired>
              <NumberInput isRequired>
                <FormLabel>Amount</FormLabel>
                <NumberInputField
                  value={giftAmount}
                  onChange={(e) => updateGiftAmount(parseInt(e.target.value))}
                  min={0.001}
                  max={1000000}
                  placeholder="$APT"
                />
              </NumberInput>
            </FormControl>
            <FormControl isRequired>
              <NumberInput isRequired>
                <FormLabel>Number of packets</FormLabel>
                <NumberInputField
                  value={numberOfPackets}
                  onChange={(e) =>
                    updatenumberOfPackets(parseInt(e.target.value))
                  }
                  min={1}
                  max={1000}
                />
              </NumberInput>
            </FormControl>
          </ModalBody>
          <ModalFooter>
            <Button
              onClick={() => handleSendGift()}
              mr={3}
              bg={niceRed}
              style={{ color: niceGold }}
            >
              {sendingGift ? <Spinner /> : "Send"}
            </Button>
            <Button onClick={onClose}>Close</Button>
          </ModalFooter>
        </ModalContent>
      </Modal>
    </>
  );
};

export default PostField;
