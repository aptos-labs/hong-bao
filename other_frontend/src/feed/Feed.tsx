import { Box, createStyles, Theme } from '@material-ui/core';
import { makeStyles } from '@material-ui/core/styles';
import React from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { AppState } from '../store';
import userActions from '../user/actions';
import { UserData } from '../user/types';
import MessageList from './MessageList';
import PostField from './PostField';
import UserList from './UserList';
import useWebSocket, { ReadyState } from 'react-use-websocket';

const useStyles = makeStyles((theme: Theme) => createStyles({
    content: {
        borderBottomColor: theme.palette.divider,
        borderBottomStyle: 'solid',
        borderBottomWidth: 1,
    },
    userList: {
        borderRightColor: theme.palette.divider,
        borderRightStyle: 'solid',
        borderRightWidth: 1,
    },
}));

type FeedProps = {
    user: UserData;
};

const Feed: React.FC<FeedProps> = ({ user }: FeedProps) => {
    const classes = useStyles();



    console.log(`Users: ${JSON.stringify(users)}`);
    console.log(`Messages: ${JSON.stringify(messages)}`);

    return (
        <Box display="flex" flexDirection="column" flexGrow={1} minHeight={0}>
            <Box className={classes.content} display="flex" flexGrow={1} minHeight={0} width="100%">
                <Box className={classes.userList} width={200}>
                    <UserList users={users}/>
                </Box>
                <MessageList messages={messages}/>
            </Box>
        </Box>
    );
};

export default Feed;
