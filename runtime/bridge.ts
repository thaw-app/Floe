//
//  bridge.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// NDJSON bridge between the Bun extension host and the Swift app.
// stdout carries protocol messages only; console output is redirected to stderr by host.ts.

export type Manifest = {
  name: string;
  title?: string;
  author?: string;
  owner?: string;
  preferences?: Preference[];
  commands?: { name: string; title?: string; mode?: string; preferences?: Preference[] }[];
};
type Preference = { name: string; title?: string; type?: string; default?: unknown };

export const ctx = {
  extDir: "",
  commandName: "",
  commandMode: "view",
  launchType: "userInitiated" as "userInitiated" | "background",
  supportPath: "",
  manifest: { name: "" } as Manifest,
};

type Sink = (line: string) => void;
const stdoutSink: Sink = (line) => {
  process.stdout.write(line);
};
let sink = stdoutSink;
// Tests replace the sink to capture messages; passing nothing restores stdout.
export function setSink(replacement: Sink = stdoutSink) {
  sink = replacement;
}

export function send(message: Record<string, unknown>) {
  sink(JSON.stringify(message) + "\n");
}

// For a message already written as JSON: a render is put together from text the renderer keeps.
export function sendLine(json: string) {
  sink(json + "\n");
}

let popHandler: () => void = () => send({ type: "exit" });
export function setPopHandler(handler: () => void) {
  popHandler = handler;
}
export function handlePop() {
  popHandler();
}

let popToRootHandler: () => void = () => {};
export function setPopToRootHandler(handler: () => void) {
  popToRootHandler = handler;
}
export function handlePopToRoot() {
  popToRootHandler();
}

// Requests the app answers later: the host sends `request` with an id, and the app sends `reply` with the same id.
// An answer that arrives in pieces comes as `replyChunk`s first; the reply still carries the whole of it.
type Waiting = { resolve: (value: unknown) => void; reject: (error: Error) => void; onChunk?: (chunk: string) => void };
const waiting = new Map<number, Waiting>();
let nextRequestId = 1;

type RequestOptions = { signal?: AbortSignal; onChunk?: (chunk: string) => void };
export function request<T = unknown>(method: string, params: Record<string, unknown> = {}, options: RequestOptions = {}): Promise<T> {
  const { signal, onChunk } = options;
  const id = nextRequestId++;
  return new Promise<T>((resolve, reject) => {
    const aborted = () => new DOMException("The request was aborted.", "AbortError");
    if (signal?.aborted) return reject(aborted());
    waiting.set(id, { resolve: resolve as (value: unknown) => void, reject, onChunk });
    signal?.addEventListener(
      "abort",
      () => {
        if (!waiting.delete(id)) return;
        send({ type: "cancelRequest", id });
        reject(aborted());
      },
      { once: true },
    );
    send({ type: "request", id, method, params });
  });
}

export function handleReplyChunk(message: { id: number; chunk: string }) {
  waiting.get(message.id)?.onChunk?.(message.chunk);
}

export function handleReply(message: { id: number; result?: unknown; error?: string }) {
  const request = waiting.get(message.id);
  if (!request) return;
  waiting.delete(message.id);
  if (message.error === undefined) request.resolve(message.result);
  else request.reject(new Error(message.error));
}
