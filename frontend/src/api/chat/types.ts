export enum ApiActionType {
  Write = "api/write",
  Read = "api/read",
}

export type WriteApiAction = {
  type: ApiActionType.Write;
  payload: Input;
};

export type ReadApiAction = {
  type: ApiActionType.Read;
  payload: Output;
};

export type ApiAction = WriteApiAction | ReadApiAction;

export enum InputType {
  Join = "join",
  Post = "post",
}

export type JoinInput = {
  type: InputType.Join;
  payload: { address: string };
};

export type PostInput = {
  type: InputType.Post;
  payload: { body: string };
};

export type Input = JoinInput | PostInput;

export enum OutputType {
  Error = "error",
  Alive = "alive",
  Joined = "joined",
  UserJoined = "user-joined",
  UserLeft = "user-left",
  Posted = "posted",
  UserPosted = "user-posted",
}

export enum OutputError {
  NotJoined = "not-joined",
  InvalidMessageBody = "invalid-message-body",
}

export type OutputResult<T> =
  | (T & { error: false })
  | {
      error: true;
      code: OutputError;
    };

export type UserOutput = {
  address: string;
  name: string;
};

export type MessageOutput = {
  id: string;
  user: UserOutput;
  body: string;
  createdAt: Date;
};

export type ErrorOutput = {
  type: OutputType.Error;
  payload: { code: OutputError };
};

export type AliveOutput = {
  type: OutputType.Alive;
};

export type JoinedOutput = {
  type: OutputType.Joined;
  payload: {
    user: UserOutput;
    others: UserOutput[];
    messages: MessageOutput[];
  };
};

export type UserJoinedOutput = {
  type: OutputType.UserJoined;
  payload: {
    user: UserOutput;
  };
};

export type UserLeftOutput = {
  type: OutputType.UserLeft;
  payload: {
    userAddress: string;
  };
};

export type PostedOutput = {
  type: OutputType.Posted;
  payload: {
    message: MessageOutput;
  };
};

export type UserPostedOutput = {
  type: OutputType.UserPosted;
  payload: {
    message: MessageOutput;
  };
};

export type Output =
  | ErrorOutput
  | AliveOutput
  | JoinedOutput
  | UserJoinedOutput
  | UserLeftOutput
  | PostedOutput
  | UserPostedOutput;

// First message we send through the websocket to join the chat room.
export type JoinChatRoomRequest = {
  // The account address of the creator of the chat room.
  chat_room_creator: string;

  // The name of the chat room. This is unique based on the creator of the chat
  // room. Under the hood this is the collection name.
  chat_room_name: string;

  // The public key of the person requesting to join the chat room.
  // This should be a hex string representation of an account ed25519 public key.
  chat_room_joiner: string;

  /// The payload that the web UI had the wallet sign to prove that the person
  /// making the request to join the room actually owns the account corresponding
  /// to the given public key. When you call window.aptos.signMessage the response
  /// contains a field called `signature`. This is a hex encoded representation of
  /// the signed message. That is what this field should be.
  signature: string;

  /// This is similar to the previous field but instead of signature, it's the message.
  full_message: string;
};
