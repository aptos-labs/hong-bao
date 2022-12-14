import { OutputResult } from '../api/chat/types';
import { UserData } from '../user/types';
import {
    FeedActionType,
    LoadFeedAction,
    MessageData,
    PostedFeedAction,
    PostedFeedActionOk,
    PostFeedAction,
    UserJoinedFeedAction,
    UserLeftFeedAction,
} from './types';

function load(messages: MessageData[], users: UserData[]): LoadFeedAction {
    return { type: FeedActionType.Load, payload: { messages, users } };
}

function post(body: string): PostFeedAction {
    return { type: FeedActionType.Post, payload: { body } };
}

function posted(result: OutputResult<PostedFeedActionOk>): PostedFeedAction {
    return { type: FeedActionType.Posted, payload: result };
}

function userJoined(user: UserData): UserJoinedFeedAction {
    return { type: FeedActionType.UserJoined, payload: { user } };
}

function userLeft(address: string): UserLeftFeedAction {
    return { type: FeedActionType.UserLeft, payload: { address } };
}

const feedActions = {
    load,
    post,
    posted,
    userJoined,
    userLeft,
};

export default feedActions;
