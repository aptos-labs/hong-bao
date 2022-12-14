import * as React from "react"
import {
    Box,
    Button,
    Card,
    CardBody,
    CardFooter,
    CardHeader,
    Flex,
    Grid,
    GridItem,
    Heading,
    SimpleGrid,
    Spacer,
    Text,
} from "@chakra-ui/react"
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useEffect, useState } from "react";
import { ChatRoom, getChatRoomsUserIsIn } from "./api/indexer";
import { getAccountAddressPretty } from "./api/ans";
import { DisconnectComponent } from "./DisconnectComponent";

export const ChatOverviewPage = () => {
    const [chatRooms, updateChatRooms] = useState<ChatRoom[] | undefined>(
        undefined,
    );

    // We use the addresses to begin with, and then the ANS names if found.
    const [creatorNames, updateCreatorNames] = useState<string[] | undefined>(undefined);

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

    console.log(`Chat rooms: ${JSON.stringify(chatRooms)}`);

    let body;
    if (chatRooms === undefined) {
        body = (<Text>Fetching chat rooms</Text>);
    } else if (chatRooms!.length === 0) {
        body = (<Text>You are not in any chat rooms!</Text>);
    } else {
        let cards = [];
        let index = 0;
        for (const chatRoom of chatRooms!) {
            let createdByString = `Created by ${creatorNames![index]}`;
            cards.push(
                <Card key={`${chatRoom.creator_address}_${chatRoom.collection_name}`}>
                    <CardHeader>
                        <Heading size='md'>{chatRoom.collection_name}</Heading>
                    </CardHeader>
                    <CardBody>
                        <Text>{createdByString}</Text>
                    </CardBody>
                    <CardFooter>
                        <Button>Join chat room</Button>
                    </CardFooter>
                </Card>);
            index += 1;
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
                <GridItem pl='2' bg='yellow.50' area={'main'}>
                    Main
                </GridItem>
                <GridItem pl='2' bg='blue.300' area={'footer'}>
                    Footer
                </GridItem>
            </Grid>
        );
    }

    return body;
}
