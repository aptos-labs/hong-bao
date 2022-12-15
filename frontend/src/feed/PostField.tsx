import { Box, createStyles, TextField, Theme } from "@material-ui/core";
import { Box as ChakraBox, Button } from "@chakra-ui/react";
import { makeStyles } from "@material-ui/core/styles";
import React, { ChangeEvent, FormEvent, useState } from "react";
import { SendJsonMessage } from "react-use-websocket/dist/lib/types";
import apiProto from "../api/chat/proto";
import { ChatStateContext } from "../ChatSection";

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

type PostFieldProps = {};

type PostFieldState = {
  body: string;
  bodyValid: boolean;
};

const PostField: React.FC<PostFieldProps> = ({}: PostFieldProps) => {
  const classes = useStyles();
  const [state, setState] = useState<PostFieldState>({
    body: "",
    bodyValid: false,
  });

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
    setState((prevState) => ({ body: "", bodyValid: false }));
    sendJsonMessage(apiProto.post(body));
  };

  return (
    <ChatStateContext.Consumer>
      {(chatState) => (
        <ChakraBox w={"95%"}>
          <Box
            component="form"
            onSubmit={(e) => handlePost(e, chatState.sendJsonMessage)}
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
              onClick={(e) => handlePost(e, chatState.sendJsonMessage)}
            >
              Send
            </Button>
            <Button
              bg="#d12d29"
              style={{ color: '#fdf9aa' }}
              className={classes.postButton}
              variant="contained"
              disabled={false}
              onClick={(e) => handlePost(e, chatState.sendJsonMessage)}
            >
              Gift
            </Button>

          </Box>
        </ChakraBox>
      )}
    </ChatStateContext.Consumer>
  );
};

export default PostField;
