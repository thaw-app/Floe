//
//  bridge.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// NDJSON bridge between the Bun extension host and the Swift app.
// stdout carries protocol messages only; console output is redirected to stderr by host.ts.
import fs from "node:fs";

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
  // Floe's own files for the extension: build, cache, local storage, preferences.
  dataPath: "",
  // environment.supportPath, the extension's alone.
  supportPath: "",
  manifest: { name: "" } as Manifest,
  // The command's preferences as the app resolved them, as JSON, or nothing when the host runs without the app.
  preferences: undefined as string | undefined,
  // The key LocalStorage seals its values with, from the app's Keychain, or nothing when the host runs without the app.
  storageKey: undefined as Buffer | undefined,
  // True when the app could not read that key: LocalStorage then saves nothing.
  storageLocked: false,
  // The sign-in that failed last, which says why a render that kept waiting on it gave up.
  signInFailure: undefined as { error: Error; at: number } | undefined,
};

// The command's Keychain values and the storage key come as the first line of the host's input, never in the
// environment: another program running as the same user can read a process's starting environment with ps.
// FLOE_SECRETS=input says the line is there; without it, as when the host runs without the app, there is none.
export function takeSecrets(readLine: () => string = () => firstLine(0)): void {
  const onInput = process.env.FLOE_SECRETS === "input";
  delete process.env.FLOE_SECRETS;
  let secrets: { preferences?: unknown; storageKey?: unknown; storageLocked?: unknown } = {};
  if (onInput) {
    try {
      secrets = JSON.parse(readLine());
    } catch {
      // Secrets that were sent but did not arrive lock the storage rather than leave it plain.
      secrets = { storageLocked: true };
    }
  }
  ctx.preferences = typeof secrets.preferences === "string" ? secrets.preferences : undefined;
  const key = Buffer.from(typeof secrets.storageKey === "string" ? secrets.storageKey : "", "base64");
  ctx.storageKey = key.length === 32 ? key : undefined;
  ctx.storageLocked = secrets.storageLocked === true;
}

// One byte at a time, so nothing after the line is taken from the messages that follow it.
function firstLine(descriptor: number): string {
  const bytes: number[] = [];
  const byte = Buffer.alloc(1);
  for (;;) {
    let read: number;
    try {
      read = fs.readSync(descriptor, byte, 0, 1, null);
    } catch (error) {
      // A non-blocking pipe with nothing in it yet: wait a moment and read again.
      if ((error as { code?: string }).code !== "EAGAIN") throw error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2);
      continue;
    }
    if (read === 0 || byte[0] === 0x0a) return Buffer.from(bytes).toString("utf8");
    bytes.push(byte[0]);
  }
}

type Sink = (line: string) => void;
let reserved: typeof process.stdout.write | undefined;
const stdoutSink: Sink = (line) => {
  (reserved ?? process.stdout.write).call(process.stdout, line);
};
// stdout is the protocol's alone. What an extension writes to process.stdout itself would be glued onto the next
// message, so from here it goes to stderr with the console output. The function returned puts it back.
export function reserveStdout(): () => void {
  const original = process.stdout.write;
  reserved = original;
  process.stdout.write = ((...args: Parameters<typeof original>) => process.stderr.write(...args)) as typeof original;
  return () => {
    process.stdout.write = original;
    reserved = undefined;
  };
}
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
