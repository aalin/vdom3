import Runtime from './runtime.js'
import { initInputStream, initCallbackStream, JSONEncoderStream, RAFQueue } from './stream.js'
import serializeEvent from "./serializeEvent.js"

class PatchStream extends WritableStream {
  constructor(runtime) {
    super({
      start(controller) {
        controller.runtime = runtime

        controller.rafQueue = new RAFQueue((patches) => {
          // console.debug("Applying", patches.length, "patches");
          // console.time("patch");
          runtime.apply(patches)
          // console.timeEnd("patch");
        });
      },
      write(patch, controller) {
        controller.rafQueue.enqueue(patch);
      },
      flush(controller) {},
    });
  }
}

const sessionId = import.meta.url.split("#").at(-1)

const endpoint = `/.vdom/session/${sessionId}`
const input = await initInputStream(endpoint)
const output = initCallbackStream(endpoint)

const runtime = new Runtime()

const callbackStream = new TransformStream()

class Mayu {
  #writer = null

  constructor(writer) {
    this.#writer = writer
  }

  callback(event, id) {
    this.#writer.write(["callback", id, serializeEvent(event)])
  }
}

window.Mayu = new Mayu(callbackStream.writable.getWriter())

input.pipeTo(new PatchStream(runtime));

callbackStream.readable
  .pipeThrough(new JSONEncoderStream())
  .pipeThrough(new TextEncoderStream())
  .pipeTo(output);
