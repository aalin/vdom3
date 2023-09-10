import Runtime from '/runtime.js'
import {connect, readInput, initCallbackStream, JSONDecoderStream, JSONEncoderStream, RAFQueue} from './stream.js'

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
const input = await connect(endpoint)
const output = initCallbackStream(endpoint)

const runtime = new Runtime()

const callbackStream = new JSONEncoderStream()
const callbackWriter = callbackStream.writable.getWriter()

window.Mayu = {
  callback(event, id) {
    callbackWriter.write([
      "callback",
      id,
      {
        id,
        type: event.type,
        target: {
          textContent: event.target.textContent
        }
      }
    ])
  }
}

readInput(input)
  .pipeThrough(new TextDecoderStream())
  .pipeThrough(new JSONDecoderStream())
  .pipeTo(new PatchStream(runtime));

callbackStream.readable
  .pipeThrough(new TextEncoderStream())
  .pipeTo(output);
