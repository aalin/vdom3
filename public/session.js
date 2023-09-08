import Runtime from '/runtime.js'
import {connect, readInput, initCallbackStream, JSONDecoderStream, JSONEncoderStream, RAFQueue} from './stream.js'

class PatchStream extends TransformStream {
  constructor(root) {
    super({
      start(controller) {
        controller.root = root;
        controller.nodes = new Map();
        controller.navigationPromise = null;

        controller.rafQueue = new RAFQueue(async (patches) => {
          console.debug("Applying", patches.length, "patches");
          console.time("patch");

          for (const patch of patches) {
            console.log(patch)
            const [type, ...args] = patch;

            const patchFn = PatchFunctions[type];

            if (!patchFn) {
              console.error("Patch not implemented:", type);
              continue;
            }

            try {
              await patchFn.apply(controller, args);
            } catch (e) {
              console.error(e);
            }
          }

          console.timeEnd("patch");
        });
      },
      transform(patch, controller) {
        controller.rafQueue.enqueue(patch);
      },
      flush(controller) {},
    });
  }
}

//
// const endpoint = this.getAttribute("src") || DEFAULT_ENDPOINT;
// const res = await connect(endpoint);
// const output = initCallbackStream(endpoint, getSessionIdHeader(res));
//
// this.#setConnectedState(true);
//
// await getInputStream(res)
//   .pipeThrough(new TextDecoderStream())
//   .pipeThrough(new JSONDecoderStream())
//   .pipeThrough(new PatchStream(endpoint, this.shadowRoot))
//   .pipeThrough(new JSONEncoderStream())
//   .pipeThrough(new TextEncoderStream())
//   .pipeTo(output);

const sessionId = import.meta.url.split("#").at(-1)

const endpoint = `/.vdom/session/${sessionId}`
console.log("connecting")
const input = await connect(endpoint)
const output = initCallbackStream(endpoint)

await readInput(input)
  .pipeThrough(new TextDecoderStream())
  .pipeThrough(new JSONDecoderStream())
  .pipeThrough(new PatchStream(`/.vdom/session/${sessionId}/patch`, document.elementRoot))
  .pipeThrough(new JSONEncoderStream())
  .pipeThrough(new TextEncoderStream())
  .pipeTo(output);
