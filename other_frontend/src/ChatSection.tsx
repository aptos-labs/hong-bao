import * as React from "react"
import {
    Box,
    Card,
    CardBody,
    CardHeader,
    Grid,
    GridItem,
    Heading,
    Spacer,
    Text,
} from "@chakra-ui/react"
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { FormEvent, useEffect, useState } from "react";
import { getChatRoomsUserIsIn } from "./api/indexer/api";
import { getAccountAddressPretty } from "./api/ans/api";
import { DisconnectComponent } from "./DisconnectComponent";
import { getChatRoomKey } from "./helpers";
import { ChatRoom } from "./api/types";
import Feed from "./feed/Feed";
import { Provider } from "react-redux";
import configureStore from "./store";
import PostField from "./feed/PostField";
import { JoinChatRoomRequest } from "./api/chat/types";
import { SignMessageResponse } from '@aptos-labs/wallet-adapter-core';
import useWebSocket, { ReadyState } from 'react-use-websocket';
import apiProto from "./api/chat/proto";


type ChatSectionProps = {
    chatRooms: ChatRoom[],
    currentChatRoomKey: string,
    signedMessage: SignMessageResponse,
};

export const ChatSection = ({ chatRooms, currentChatRoomKey, signedMessage }: ChatSectionProps) => {
    // Websocket messages, not chat messages.
    const { sendJsonMessage, lastJsonMessage, readyState } = useWebSocket("ws://localhost:8888/chat");

    const [joinRequestSent, updatejoinRequestSent] = useState<boolean>(false);

    const {
        account,
    } = useWallet();

    const chatRoom = chatRooms!.find((chatRoom) => getChatRoomKey(chatRoom) === currentChatRoomKey)!;

    useEffect(() => {
        console.log(`joinRequestSent: ${joinRequestSent}`);
        if (!joinRequestSent) {
            // For some reason this is still getting called twice even with the check.
            // https://stackoverflow.com/questions/60618844/react-hooks-useeffect-is-called-twice-even-if-an-empty-array-is-used-as-an-ar
            updatejoinRequestSent(true);
            const joinChatRoomRequest: JoinChatRoomRequest = {
                chat_room_creator: chatRoom.creator_address,
                chat_room_name: chatRoom.collection_name,
                chat_room_joiner: account!.address,
                signature: signedMessage!.signature,
                message: signedMessage!.message,
            };
            console.log(`Sending initial auth request: ${JSON.stringify(joinChatRoomRequest)}`);
            sendJsonMessage(joinChatRoomRequest);

            const joinRequest = apiProto.join(joinChatRoomRequest.chat_room_joiner);
            console.log(`Sending followup join request: ${JSON.stringify(joinRequest)}`);
            sendJsonMessage(joinRequest);
        }
    }, []);

    useEffect(() => {
        if (lastJsonMessage !== null) {
            console.log("lastMessage", lastJsonMessage);
            // With this we can look for the message with type=joined and then
            // update the users and messages in the chat room. These and the
            // websocket can then be passed down (perhaps with a Provider) to
            // the components below (Feed and PostField).
        }
    }, [lastJsonMessage]);

    /*
      let activeFeed = <Text>Select a chat or start a new conversation</Text>;
      if (currentChatRoomKey !== undefined) {
          activeFeed = (
              <Feed user={{address: account!.address, name: account!.address}} />
          );
          footer = (
              <Provider store={store}>
                  <PostField user={{ address: account!.address, name: account!.address }} />
              </Provider>
          );
      }

          activeFeed = (
              <Feed user={{address: account!.address, name: account!.address}} />
          );
          footer = (
              <Provider store={store}>
                  <PostField user={{ address: account!.address, name: account!.address }} />
              </Provider>
          );
          const chatRoom = chatRooms!.find((chatRoom) => getChatRoomKey(chatRoom) === currentChatRoomKey)!;
          const joinChatRoomRequest: JoinChatRoomRequest = {
              chat_room_creator: chatRoom.creator_address,
              chat_room_name: chatRoom.collection_name,
              chat_room_joiner: account!.address,
              signature: signedMessage!.signature,
              message: signedMessage!.message,
          };
          if (store === undefined) {
              store = configureStore("ws://localhost:8888/chat", joinChatRoomRequest);
              console.log("Created store");
          }
          */
    return (
        <>
        </>
        /*
            <GridItem pl='2' bg='yellow.50' area={'main'}>
                <Feed user={{address: account!.address, name: account!.address}} />
            </GridItem>
            <GridItem pl='2' bg='blue.300' area={'footer'}>
                <PostField user={{ address: account!.address, name: account!.address }} />
            </GridItem>
        */
    );
}
