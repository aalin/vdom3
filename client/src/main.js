import Runtime from "./runtime.js";

import {
  initInputStream,
  initCallbackStream,
  JSONEncoderStream,
} from "./stream.js";

import serializeEvent from "./serializeEvent.js";
import { decodeMultiStream, ExtensionCodec } from "@msgpack/msgpack";

import { SESSION_MIME_TYPE } from "./constants";

class Mayu {
  #writer = null;

  constructor(writer) {
    this.#writer = writer;
  }

  callback(event, id) {
    this.#writer.write(["callback", id, serializeEvent(event)]);
  }
}

async function startPatchStream(runtime, endpoint) {
  const extensionCodec = createExtensionCodec();

  while (true) {
    const input = await initInputStream(endpoint, { extensionCodec });

    for await (const patch of decodeMultiStream(input)) {
      runtime.apply(patch);
    }
  }
}

function createExtensionCodec() {
  const extensionCodec = new ExtensionCodec();

  extensionCodec.register({
    type: 0x01,
    encode() {
      throw new Error("Not implemented");
    },
    decode(buffer) {
      return new Blob([buffer], { type: SESSION_MIME_TYPE });
    },
  });

  return extensionCodec;
}

const SESSION_PATH = "/.mayu/session";

const sessionId = import.meta.url.split("#").at(-1);

const endpoint = `${SESSION_PATH}/${sessionId}`;
const runtime = new Runtime();

const callbackStream = new TransformStream();
window.Mayu = new Mayu(callbackStream.writable.getWriter());

startPatchStream(runtime, endpoint);

const output = initCallbackStream(endpoint);

callbackStream.readable
  .pipeThrough(new JSONEncoderStream())
  .pipeThrough(new TextEncoderStream())
  .pipeTo(output);
