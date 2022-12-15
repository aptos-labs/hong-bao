import { call, fork, put, StrictEffect, take } from '@redux-saga/core/effects';
import { eventChannel, EventChannel } from 'redux-saga';
import userActions from '../../user/actions';
import apiActions from './actions';
import apiProto from './proto';
import { ApiActionType, JoinChatRoomRequest, Output, WriteApiAction } from './types';

function createWebSocketChannel(webSocket: WebSocket, joinChatRoomRequest: JoinChatRoomRequest): EventChannel<Output> {
    return eventChannel<Output>((emit) => {
        webSocket.onopen = (): void => {
            // Send the auth message.
            webSocket.send(JSON.stringify(joinChatRoomRequest));
            // Send the join request.
            webSocket.send(JSON.stringify(apiProto.join(joinChatRoomRequest.chat_room_joiner)));
        };
        webSocket.onmessage = (event): void => {
            const output = JSON.parse(event.data) as Output;
            console.log("Got message", output);
            emit(output);
        };
        webSocket.onclose = (event): void => {
            // TODO: This happens if the user was rejected / something went wrong with
            // processing the first message on the server side. Make the UI react to
            // this since we're not actually connected to the chat room, the websocket
            // is gone.
            console.log("Websocket closed okay", event);
        };
        return (): void => {
            webSocket.close();
        };
    });
}

function* connectWebSocket(url: string, joinChatRoomRequest: JoinChatRoomRequest): Generator<StrictEffect> {
    const webSocket = new WebSocket(url);
    const webSocketChannel = (yield call(createWebSocketChannel, webSocket, joinChatRoomRequest)) as EventChannel<Output>;
    yield fork(read, webSocketChannel);
    yield fork(write, webSocket);
}

function* read(webSocketChannel: EventChannel<Output>): Generator<StrictEffect> {
    while (true) {
        const output = (yield take(webSocketChannel)) as Output;
        yield put(apiActions.read(output));
    }
}

function* write(webSocket: WebSocket): Generator<StrictEffect> {
    while (true) {
        const action = (yield take(ApiActionType.Write)) as WriteApiAction;
        webSocket.send(JSON.stringify(action.payload));
    }
}

export default function* apiSaga(url: string, joinChatRoomRequest: JoinChatRoomRequest): Generator<StrictEffect> {
    return;
    yield call(() => connectWebSocket(url, joinChatRoomRequest));
}
