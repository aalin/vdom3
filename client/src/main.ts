import Runtime from "./runtime.js";

import {
  initInputStream,
  initCallbackStream,
  JSONEncoderStream,
} from "./stream.js";

import serializeEvent from "./serializeEvent.js";
import { decodeMultiStream, ExtensionCodec } from "@msgpack/msgpack";

import { SESSION_MIME_TYPE, SESSION_PATH } from "./constants";

declare global {
  interface Window {
    Mayu: Mayu;
  }
}

class Mayu {
  #writer: WritableStreamDefaultWriter<any>;

  constructor(writer: WritableStreamDefaultWriter<any>) {
    this.#writer = writer;
  }

  callback(event: Event, id: string) {
    this.#writer.write(["callback", id, serializeEvent(event)]);
  }
}

async function startPatchStream(runtime: Runtime, endpoint: string) {
  const extensionCodec = createExtensionCodec();

  while (true) {
    const input = await initInputStream(endpoint);

    for await (const patch of decodeMultiStream(input, { extensionCodec })) {
      runtime.apply(patch as any);
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
