import { ChatRoom } from "./api/types";
import { isEqual } from 'lodash';

export function getChatRoomKey(chatRoom: ChatRoom): string {
    return `${chatRoom.creator_address}:${chatRoom.collection_name}`;
}

export function removeDuplicates<T>(array: T[]): T[] {
    const result: T[] = [];
    for (const item of array) {
        const found = result.some((value) => isEqual(value, item));
        if (!found) {
            result.push(item);
        }
    }
    return result;
}
