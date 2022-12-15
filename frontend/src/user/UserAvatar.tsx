import { Avatar } from "@material-ui/core";
import chroma from "chroma-js";
import React from "react";
import { UserData } from "./types";

type UserAvatarProps = {
  user: UserData;
};

// Component that creates a little user avatar, with a background color derived
// from the user's address.
const UserAvatar: React.FC<UserAvatarProps> = ({ user }: UserAvatarProps) => {
  // Credit: https://werxltd.com/wp/2010/05/13/javascript-implementation-of-javas-string-hashcode-method/
  let hash = 0,
    i,
    chr;
  for (i = 0; i < user.address.length; i++) {
    chr = user.address.charCodeAt(i);
    hash = (hash << 5) - hash + chr;
    hash |= 0;
  }
  const background = chroma
    .hsl(Math.abs(hash) % 360, 0.7, 0.6)
    .hex()
    .substr(1);
  return (
    <Avatar
      alt={user.address}
      src={`https://eu.ui-avatars.com/api/?name=${user.address}&size=128&color=ffffff&background=${background}`}
    />
  );
};

export default UserAvatar;
