import { OutputResult } from '../api/chat/types';
import { JoinedUserAction, JoinedUserActionOk, JoinUserAction, UserActionType } from './types';

function join(address: string): JoinUserAction {
    return { type: UserActionType.Join, payload: { address } };
}

function joined(result: OutputResult<JoinedUserActionOk>): JoinedUserAction {
    return { type: UserActionType.Joined, payload: result };
}

const userActions = {
    join,
    joined,
};

export default userActions;
