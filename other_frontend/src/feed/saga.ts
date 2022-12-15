import { put, StrictEffect, take, takeEvery } from '@redux-saga/core/effects';
import apiActions from '../api/chat/actions';
import apiProto from '../api/chat/proto';
import { ApiActionType, OutputType, ReadApiAction } from '../api/chat/types';
import userActions from '../user/actions';
import { JoinedUserAction, UserActionType } from '../user/types';
import feedActions from './actions';
import { FeedActionType, PostFeedAction } from './types';

function* handleUserJoined(action: JoinedUserAction): Generator<StrictEffect> {
    if (!action.payload.error) {
        const messages = action.payload.messages.map((message) => ({
            ...message,
            createdAt: new Date(message.createdAt),
        }));
        yield put(feedActions.load(messages, action.payload.others));
    }
}

function* handlePost(action: PostFeedAction): Generator<StrictEffect> {
    yield put(apiActions.write(apiProto.post(action.payload.body)));

    while (true) {
        const read = (yield take(ApiActionType.Read)) as ReadApiAction;

        if (read.payload.type === OutputType.Error) {
            yield put(feedActions.posted({ error: true, code: read.payload.payload.code }));
            break;
        } else if (read.payload.type === OutputType.Posted) {
            const output = read.payload.payload;
            yield put(feedActions.posted({
                error: false,
                message: {
                    ...output.message,
                    createdAt: new Date(output.message.createdAt),
                },
            }));
            break;
        }
    }
}

function* handleApiRead(action: ReadApiAction): Generator<StrictEffect> {
    switch (action.payload.type) {
        case OutputType.UserPosted:
            console.log("user posted");
            const message = action.payload.payload.message;
            yield put(feedActions.posted({
                error: false,
                message: {
                    ...message,
                    createdAt: new Date(message.createdAt),
                },
            }));
            break;
        case OutputType.UserJoined:
            console.log("user joined");
            yield put(userActions.join(action.payload.payload.user.address));
            yield put(feedActions.userJoined(action.payload.payload.user));
            break;
        case OutputType.UserLeft:
            console.log("user left");
            yield put(feedActions.userLeft(action.payload.payload.userAddress));
            break;
    }
}

export function* feedSaga(): Generator<StrictEffect> {
    yield takeEvery(UserActionType.Joined, handleUserJoined);
    yield takeEvery(FeedActionType.Post, handlePost);
    yield takeEvery(ApiActionType.Read, handleApiRead);
}
