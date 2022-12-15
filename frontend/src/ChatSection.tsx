import * as React from "react";
import { Box, Button, GridItem } from "@chakra-ui/react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useEffect, useState } from "react";
import { getChatRoomKey } from "./helpers";
import { ChatRoom } from "./api/types";
import Feed from "./feed/Feed";
import PostField from "./feed/PostField";
import { JoinChatRoomRequest, Output, OutputType } from "./api/chat/types";
import { SignMessageResponse } from "@aptos-labs/wallet-adapter-core";
import useWebSocket, { ReadyState } from "react-use-websocket";
import apiProto from "./api/chat/proto";
import { MessageData } from "./feed/types";
import { UserData } from "./user/types";
import { SendJsonMessage } from "react-use-websocket/dist/lib/types";

// This should contain everything the lower components need to read the chat
// state as well as send websocket messages back to the server.
type ChatState = {
  chatRoom: ChatRoom;
  messages: MessageData[];
  users: UserData[];
  user: UserData;
  sendJsonMessage: SendJsonMessage; // This is a function.
  currentChatRoomKey: string;
};

type ChatSectionProps = {
  chatRooms: ChatRoom[];
  currentChatRoomKey: string;
  signedMessage: SignMessageResponse;
  backendUrl: string;
};

export const ChatStateContext = React.createContext<ChatState>({} as ChatState);

export const ChatSection = ({
  chatRooms,
  currentChatRoomKey,
  signedMessage,
  backendUrl,
}: ChatSectionProps) => {
  // Websocket messages, not chat messages.
  const { sendJsonMessage, lastJsonMessage, readyState } =
    useWebSocket(backendUrl);

  const [joinRequestSent, updatejoinRequestSent] = useState<boolean>(false);

  const { account } = useWallet();

  const chatRoom = chatRooms!.find(
    (chatRoom) => getChatRoomKey(chatRoom) === currentChatRoomKey
  )!;

  const [chatState, updateChatState] = useState<ChatState>({
    chatRoom: chatRoom,
    messages: [],
    users: [],
    user: {
      address: account!.address,
      name: account!.address,
    },
    sendJsonMessage,
    currentChatRoomKey,
  });

  useEffect(() => {
    if (!joinRequestSent) {
      console.log(`Connecting to ${backendUrl}`);

      // For some reason this is still getting called twice even with the check.
      // https://stackoverflow.com/questions/60618844/react-hooks-useeffect-is-called-twice-even-if-an-empty-array-is-used-as-an-ar
      // Only disabling strict mode fixed it.
      updatejoinRequestSent(true);
      const joinChatRoomRequest: JoinChatRoomRequest = {
        chat_room_creator: chatRoom.creator_address,
        chat_room_name: chatRoom.collection_name,
        chat_room_joiner: account!.publicKey,
        signature: signedMessage!.signature,
        full_message: signedMessage!.fullMessage,
      };
      console.log(
        `Sending initial auth request: ${JSON.stringify(joinChatRoomRequest)}`
      );
      sendJsonMessage(joinChatRoomRequest);

      const joinRequest = apiProto.join(joinChatRoomRequest.chat_room_joiner);
      console.log(
        `Sending followup join request: ${JSON.stringify(joinRequest)}`
      );
      sendJsonMessage(joinRequest);
    }
  }, []);

  useEffect(() => {
    if (lastJsonMessage === null) {
      return;
    }

    // Here we process messages from the server and use it to update the users and
    // messages in the chat room.
    const output = lastJsonMessage as Output;
    switch (output.type) {
      // Careful here, the updateChatState function doesn't seem to typecheck the
      // new state correctly.
      case OutputType.Joined:
        updateChatState((prevChatState) => ({
          ...prevChatState,
          users: output.payload.others.concat([output.payload.user]),
          messages: output.payload.messages.reverse(),
        }));
        console.log("We joined");
        break;
      case OutputType.Posted:
        updateChatState((prevChatState) => ({
          ...prevChatState,
          messages: [output.payload.message].concat(prevChatState.messages),
        }));
        console.log("We sent a message");
        break;
      case OutputType.UserPosted:
        console.log("Another user sent a message");
        updateChatState((prevChatState) => ({
          ...prevChatState,
          messages: [output.payload.message].concat(prevChatState.messages),
        }));
        break;
      case OutputType.UserJoined:
        console.log("Another user joined");
        updateChatState((prevChatState) => ({
          ...prevChatState,
          users: [output.payload.user].concat(prevChatState.users),
        }));
        break;
      case OutputType.UserLeft:
        console.log("Another user left");
        updateChatState((prevChatState) => ({
          ...prevChatState,
          users: prevChatState.users.filter(
            (user) => user.address !== output.payload.userAddress
          ),
        }));
        break;
    }
  }, [lastJsonMessage]);

  const connectionStatus = {
    [ReadyState.CONNECTING]: "Connecting",
    [ReadyState.OPEN]: "Open",
    [ReadyState.CLOSING]: "Closing",
    [ReadyState.CLOSED]: "Closed",
    [ReadyState.UNINSTANTIATED]: "Uninstantiated",
  }[readyState];
  console.log("connectionStatus: " + connectionStatus);

  return (
    <ChatStateContext.Provider value={chatState}>
      <GridItem
        pl="2"
        bg="yellow.50"
        area={"main"}
        display="flex"
        mt="2"
        alignItems="bottom"
      >
        <Feed />
      </GridItem>
      <GridItem
        pl="2"
        bg="blue.300"
        area={"footer"}
        display="flex"
        alignItems="bottom"
      >
        <Box w={"100%"} display="flex">
          <PostField currentChatRoomKey={currentChatRoomKey} />
        </Box>
      </GridItem>
    </ChatStateContext.Provider>
  );
};
