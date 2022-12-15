import { InputType, JoinInput, PostInput } from "./types";

function join(address: string): JoinInput {
  return { type: InputType.Join, payload: { address } };
}

function post(body: string): PostInput {
  return { type: InputType.Post, payload: { body } };
}

const apiProto = {
  join,
  post,
};

export default apiProto;
