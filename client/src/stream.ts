// Copyright Andreas Alin <andreas.alin@gmail.com>
// License: AGPL-3.0

import { STREAM_MIME_TYPE, STREAM_CONTENT_ENCODING } from "./constants";
import supportsRequestStreams from "./supportsRequestStreams";

export async function initInputStream(
  endpoint: string
): Promise<ReadableStream<any>> {
  const res = await connect(endpoint);

  if (!res.body) throw new Error("No body");

  const contentEncoding = res.headers.get("content-encoding");

  if (!contentEncoding) return res.body;

  return res.body.pipeThrough(new DecompressionStream(contentEncoding as any));
}

export async function connect(endpoint: string): Promise<Response> {
  console.info("🟡 Connecting to", endpoint);

  const res = await fetch(endpoint, {
    method: "GET",
    credentials: "include",
    headers: new Headers({
      accept: STREAM_MIME_TYPE,
      "accept-encoding": STREAM_CONTENT_ENCODING,
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

export class RAFQueue<T> {
  onFlush: (queue: T[]) => void;
  queue: T[];
  raf: number | null;

  constructor(onFlush: (queue: T[]) => void) {
    this.onFlush = onFlush;
    this.queue = [];
    this.raf = null;
  }

  enqueue(messages: T[]) {
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

export function initCallbackStream(endpoint: string) {
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
  } as any);

  return writable;
}

function initCallbackStreamFetchFallback(endpoint: string) {
  return new WritableStream({
    write(body) {
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
