import { ChatRoom } from "./api/types";
import { isEqual } from "lodash";

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

export function getShortAddress(addr: string) {
  return "0x" + addr.substring(0, 4) + "..." + addr.substring(addr.length - 4);
}

export const niceRed = "#d12d29";
export const niceGold = "#fdf9aa";

export function getExpirationTimePretty(unixtimeSecs: number) {
  // If the time is in the past, return "Expired".
  if (unixtimeSecs < Date.now() / 1000) {
    return "Expired.";
  }

  // Create a new JavaScript Date object based on the timestamp
  // multiplied by 1000 so that the argument is in milliseconds, not seconds.
  var date = new Date(unixtimeSecs * 1000);
  // Hours part from the timestamp
  var hours = date.getHours();
  // Minutes part from the timestamp
  var minutes = "0" + date.getMinutes();
  // Seconds part from the timestamp
  var seconds = "0" + date.getSeconds();

  // Will display time in 10:30:23 format
  var formattedTime =
    hours + ":" + minutes.substr(-2) + ":" + seconds.substr(-2);

  return formattedTime;
}
