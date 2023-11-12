import Runtime from './runtime.js'
import { initInputStream, initCallbackStream, JSONEncoderStream, RAFQueue } from './stream.js'
import serializeEvent from "./serializeEvent.js"
import {decodeMultiStream} from '@msgpack/msgpack'

class Mayu {
  #writer = null

  constructor(writer) {
    this.#writer = writer
  }

  callback(event, id) {
    this.#writer.write(["callback", id, serializeEvent(event)])
  }
}

async function runPatchStream(runtime) {
  while (true) {
    const input = await initInputStream(endpoint)

    for await (const patch of decodeMultiStream(input)) {
      runtime.apply(patch)
    }
  }
}

const SESSION_PATH = "/.mayu/session"

const sessionId = import.meta.url.split("#").at(-1)

const endpoint = `${SESSION_PATH}/${sessionId}`
const output = initCallbackStream(endpoint)

const runtime = new Runtime()

const callbackStream = new TransformStream()
window.Mayu = new Mayu(callbackStream.writable.getWriter())

runPatchStream(runtime)

callbackStream.readable
  .pipeThrough(new JSONEncoderStream())
  .pipeThrough(new TextEncoderStream())
  .pipeTo(output);
