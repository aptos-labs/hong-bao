# Into 2023 Hackathon: Hong Bao 🧧

Hello!!

# User Story

##High level journey 

We want to be able to let users:

1. Create a Friend / Social group - ideally within petra. Or connected to Petra (maybe using wallet connect?)
2. Chat within the social group - this part does not have to be on-chain necessarily
3. Disburse Hong-Baos
4. Snatch Hong Baos
5. Collect the APT in the Hong Baos in Owner Account

## Detailed Journey

1. John, Robin, Mary, Fred are friends in real life
2. In Wallet, they are able to create a group based on their user addresses, and named their group “Lil Degens”. UI -
    1. Press create Group
    2. Name Group
    3. Add members to group based on wallet address [can also add by ANS]
    4. [optional] can give self nickname in the group, easier for identification
    5. Mock: 
    6. can also join existing groups by direct link
3. Alt flow: 
    1. Someone makes a new group. Behind the scenes this makes essentially a new soulbound NFT collection.
    2. As part of this, they mint tokens that they offer to everyone they invited.
    3. An invited user opens the web UI, connects their wallet, and sees somewhere in the UI that they’ve been invited to a chat.
    4. Accepting the invite behind the scenes accepts the NFT.
    5. Now they’re in the group.
4. [Optional / Further development] Groups can be formed on the basis of NFT ownership
    1. Publicly discoverable groups, with persons being able to ask to join
    2. Auto-accept based on NFT ownership [i.e. Aptos Monkeys groups, all holders can ask-join, and will get automatically accepted]
    3. But also a version where the admin can manually approve joiners
    4. Chat and Hong Bao functionality will be the same once they are in the group
5. In the group, there is chat functionality, they are able to send each other messages. Just text for now to keep things simple
6. They are also able to send each other group Hong Baos. Flow - 
    1. Anyone in group can share a hongbao. They click Send Hong Bao. 
    2. Set Total APT amount
    3. Total Hong Baos
    4. Expiry time of the set. I.e. time in seconds until when the contract would auto-expire
        1. Any unclaimed hong baos (APT) would go back to the original sender account
    5. Optional - allow sender to enable or disable repeated snatches. I.e. the same person / owner address can snatch more than 1 hong bao within the set. 
        1. Probably P0 is that this is auto-disable, so each person can only grab one hong bao
        2. If there are more hong baos than persons 
    6. The smart contract would auto-randomize the amount of APT within each Hong Bao
    7. For example, total 10 APT, across 5 hong baos. Some of the hong baos would have 1 APT, some might have 0.2 APT.
7. For the other members, they would see an image of a hong bao appear.
8. [Optional - notification to all group members when new instance of chat or hong bao appears]
9. They have to snatch the hong bao by clicking on the image. 
10. [Optional] The location of the Hong bao might be randomized, not just in the middle of the screen to increase the difficulty of the snatching
11. Once they snatch the closed hongbao, there would be an image of an Open Hong Bao with the APT amount they are receiving. This would fade after 2 seconds. If the user checks their wallet balance, they would see the APT increase by a corresponding amount

# Other future development

1. Discord owners (like NFT collections) can organize gamified giveaways for their holders like this, using a mass import function)
