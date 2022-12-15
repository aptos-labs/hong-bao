import { OutputError, OutputResult } from "../api/chat/types";
import { MessageData } from "../feed/types";

export type UserData = {
  // Account address.
  address: string;

  // Name, todo think about how to get this, it'll be an ANS lookup.
  name: string;
};

export type UserState = {
  currentUser: UserData | null;
  joinError: OutputError | null;
};

export enum UserActionType {
  Join = "user/join",
  Joined = "user/joined",
}

export type JoinUserAction = {
  type: UserActionType.Join;
  payload: { address: string };
};

export type JoinedUserAction = {
  type: UserActionType.Joined;
  payload: OutputResult<JoinedUserActionOk>;
};

export type JoinedUserActionOk = {
  user: UserData;
  others: UserData[];
  messages: MessageData[];
};

export type UserAction = JoinUserAction | JoinedUserAction;
