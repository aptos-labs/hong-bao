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
import { SignMessageResponse } from '@aptos-labs/wallet-adapter-core';
import { ChatSection } from "./ChatSection";

export const ChatOverviewPage = () => {
    const [chatRooms, updateChatRooms] = useState<ChatRoom[] | undefined>(
        undefined,
    );

    // We use the addresses to begin with, and then the ANS names if found.
    const [creatorNames, updateCreatorNames] = useState<string[] | undefined>(undefined);

    // Probably doesn't belong here but here we maintain the chat room connection
    // objects keyed by chat room ID.
    const [currentChatRoomKey, updateCurrentChatRoomKey] = useState<string | undefined>(
        undefined,
    );

    const [signedMessage, updateSignedMessage] = useState<SignMessageResponse | undefined>(
        undefined,
    );

    let store = undefined;

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

    const updateCreatorNameWrapper = async (address: string, index: number) => {
        const name = await getAccountAddressPretty(address);
        if (name === address) {
            return;
        }
        const newCreatorNames = creatorNames!;
        newCreatorNames[index] = name;
        updateCreatorNames(newCreatorNames);
    }

    const handleJoinRoom = (e: FormEvent, chatRoomKey: string) => {
        e.preventDefault();

        // In order to connect we need to have had the user sign a message message first.
        // Once that is done, then we update the current chat room key, which will trigger
        // an attempt to connect to the room.
        const signMessageWrapper = async () => {
            if (signedMessage === undefined) {
                const response = await signMessage({
                    message: "What is this for you ask? Signing this message allows the server to verify that you are the real owner of the account you are trying to connect as.", nonce: `${Math.floor(Math.random() * 100000)}`
                });
                if (response !== null) {
                    updateSignedMessage(response);
                }
            }
            updateCurrentChatRoomKey(chatRoomKey);
            console.log(`New chat room key: ${chatRoomKey}`);
        };

        signMessageWrapper();
    }

    useEffect(() => {
        console.log("use effect");
        const updateChatRoomsWrapper = async () => {
            // Get chat rooms.
            const chatRooms = await getChatRoomsUserIsIn(account!.address);

            // Set creator names as addresses for now.
            let currentCreatorNames = chatRooms.map((chatRoom) => chatRoom.creator_address);
            updateCreatorNames(currentCreatorNames);

            updateChatRooms(chatRooms);

            // Kick off promises to update the creator names based on what we
            // read from ANS (if a name is found).
            for (let i = 0; i < chatRooms.length; i++) {
                updateCreatorNameWrapper(currentCreatorNames[i], i);
            }
        }
        updateChatRoomsWrapper();
    }, []);

    let body;
    if (chatRooms === undefined) {
        body = (<Text>Fetching chat rooms</Text>);
    } else if (chatRooms!.length === 0) {
        body = (<Text>You are not in any chat rooms!</Text>);
    } else {
        let cards = [];
        let index = 0;
        for (const chatRoom of chatRooms!) {
            const createdByString = `Created by ${creatorNames![index]}`;
            const chatRoomKey = getChatRoomKey(chatRoom);
            let bg = undefined;
            if (chatRoomKey === currentChatRoomKey) {
                bg = 'gray.200';
            }
            cards.push(
                <Card onClick={(e) => handleJoinRoom(e, chatRoomKey)} margin={3} bg={bg} key={chatRoomKey}>
                    <CardHeader>
                        <Heading size='md'>{chatRoom.collection_name}</Heading>
                    </CardHeader>
                    <CardBody>
                        <Text>{createdByString}</Text>
                    </CardBody>
                </Card>);
            index += 1;
        }

        let chatSection = (<Text>Click on a chat room to join it!</Text>);
        if (currentChatRoomKey !== undefined && signedMessage !== undefined) {
            chatSection = (
                <ChatSection chatRooms={chatRooms} currentChatRoomKey={currentChatRoomKey} signedMessage={signedMessage as SignMessageResponse} />
            );
        }

        body = (
            <Grid
                templateAreas={`"nav header"
                  "nav main"
                  "nav footer"`}
                gridTemplateRows={'10% 80% 5%'}
                gridTemplateColumns={'30% 70%'}
                h='calc(100vh)'
                gap='4'
                color='blackAlpha.700'
                fontWeight='bold'
            >
                <GridItem pl='2' bg='red.800' area={'header'} display='flex' mt='2' alignItems='center'>
                    <Spacer />
                    <DisconnectComponent />
                    <Box w={"3%"} />
                </GridItem>
                <GridItem pl='2' bg='gray.50' area={'nav'}>
                    <Box h={"1%"} />
                    <Heading textAlign={"center"}>Chats</Heading>
                    <Box h={"2%"} />
                    {cards}
                </GridItem>
                {chatSection}
            </Grid>
        );
    }

    return body;
}
