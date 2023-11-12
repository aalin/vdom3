// Copyright Andreas Alin <andreas.alin@gmail.com>
// License: AGPL-3.0

import { STREAM_MIME_TYPE, STREAM_CONTENT_ENCODING } from "./constants";

export async function initInputStream(endpoint) {
  const res = await connect(endpoint);

  const contentEncoding = res.headers.get("content-encoding");

  return res.body.pipeThrough(new DecompressionStream(contentEncoding));
}

export async function connect(endpoint) {
  console.info("🟡 Connecting to", endpoint);

  const acceptEncoding =
    typeof DecompressionStream !== "undefined"
      ? STREAM_CONTENT_ENCODING
      : "identity";

  const res = await fetch(endpoint, {
    method: "GET",
    credentials: "include",
    headers: new Headers({
      accept: STREAM_MIME_TYPE,
      "accept-encoding": acceptEncoding,
    }),
  });

  if (!res.ok) {
    alert("Connection failed!");
    console.error(res);
    throw new Error("Res was not ok.");
  }

  const contentType = res.headers.get("content-type");

  if (contentType !== STREAM_MIME_TYPE) {
    alert(`Unexpected content type: ${contentType}`);
    console.error(res);
    throw new Error(`Unexpected content type: ${contentType}`);
  }

  console.info("🟢 Connected to", endpoint);

  return res;
}

export class RAFQueue {
  constructor(onFlush) {
    this.onFlush = onFlush;
    this.queue = [];
    this.raf = null;
  }

  enqueue(messages) {
    messages.forEach((msg) => this.queue.push(msg));
    this.raf ||= requestAnimationFrame(() => this.flush());
  }

  flush() {
    this.raf = null;
    const queue = this.queue;
    if (queue.length === 0) return;
    this.queue = [];
    this.onFlush(queue);
  }
}

export class JSONEncoderStream extends TransformStream {
  constructor() {
    super({
      transform(chunk, controller) {
        controller.enqueue(JSON.stringify(chunk) + "\n");
      },
    });
  }
}

const supportsRequestStreams = (() => {
  // https://developer.chrome.com/articles/fetch-streaming-requests/#feature-detection
  let duplexAccessed = false;

  const hasContentType = new Request("", {
    body: new ReadableStream(),
    method: "POST",
    get duplex() {
      duplexAccessed = true;
      return "half";
    },
  }).headers.has("Content-Type");

  return duplexAccessed && !hasContentType;
})();

export function initCallbackStream(endpoint) {
  if (!supportsRequestStreams) {
    console.warn("Request streams not supported, using fallback.");
    return initCallbackStreamFetchFallback(endpoint);
  }

  const contentEncoding = "identity"; // STREAM_CONTENT_ENCODING;
  const { readable, writable } = new TransformStream(); // new CompressionStream(contentEncoding);

  fetch(endpoint, {
    method: "POST",
    headers: new Headers({
      "content-type": STREAM_MIME_TYPE,
      "content-encoding": contentEncoding,
    }),
    duplex: "half",
    mode: "cors",
    body: readable,
  });

  return writable;
}

function initCallbackStreamFetchFallback(endpoint) {
  return new WritableStream({
    write(body, controller) {
      fetch(endpoint, {
        method: "POST",
        headers: new Headers({
          "content-type": "application/json",
        }),
        mode: "cors",
        body: body,
      });
    },
  });
}
