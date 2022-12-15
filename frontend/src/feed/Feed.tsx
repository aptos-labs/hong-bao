import { Box, createStyles, Theme } from "@material-ui/core";
import { makeStyles } from "@material-ui/core/styles";
import React from "react";
import { ChatStateContext } from "../ChatSection";
import MessageList from "./MessageList";
import UserList from "./UserList";

const useStyles = makeStyles((theme: Theme) =>
  createStyles({
    content: {
      borderBottomColor: theme.palette.divider,
      borderBottomStyle: "solid",
      borderBottomWidth: 1,
    },
    userList: {
      borderRightColor: theme.palette.divider,
      borderRightStyle: "solid",
      borderRightWidth: 1,
    },
  })
);

type FeedProps = {};

const Feed: React.FC<FeedProps> = ({}: FeedProps) => {
  const classes = useStyles();

  return (
    <ChatStateContext.Consumer>
      {(state) => {
        return (
          <Box display="flex" flexDirection="column" flexGrow={1} minHeight={0}>
            <Box
              className={classes.content}
              display="flex"
              flexGrow={1}
              minHeight={0}
              width="100%"
            >
              <MessageList messages={state.messages} />
              <Box className={classes.userList} width={275}>
                <UserList users={state.users} />
              </Box>
            </Box>
          </Box>
        );
      }}
    </ChatStateContext.Consumer>
  );
};

export default Feed;
