//
//  network.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Node's fetch takes certificate and proxy settings from an agent or an undici dispatcher; Bun's takes them as
// tls and proxy, and ignores the others. Self-hosted servers with their own certificate, and proxies, need them.

type TLS = { rejectUnauthorized?: boolean; ca?: unknown; cert?: unknown; key?: unknown };
type Settings = { tls?: TLS; proxy?: string };
type Init = RequestInit & { agent?: unknown; dispatcher?: object; tls?: TLS; proxy?: string };

/// What each undici Agent or ProxyAgent was made with: Bun's keep none of it.
export const dispatchers = new WeakMap<object, Settings>();
let globalDispatcher: object | undefined;

export function setGlobalDispatcher(dispatcher: object | undefined) {
  globalDispatcher = dispatcher;
}

export function getGlobalDispatcher() {
  return globalDispatcher;
}

export function pickTLS(source: unknown): TLS | undefined {
  if (typeof source !== "object" || source === null) return undefined;
  const record = source as Record<string, unknown>;
  const picked = Object.fromEntries(["rejectUnauthorized", "ca", "cert", "key"].filter((key) => record[key] !== undefined).map((key) => [key, record[key]]));
  return Object.keys(picked).length > 0 ? picked : undefined;
}

// https.Agent keeps its options; https-proxy-agent and its kin keep the proxy's URL.
function agentSettings(agent: unknown): Settings {
  if (typeof agent !== "object" || agent === null) return {};
  const { options, proxy } = agent as { options?: unknown; proxy?: unknown };
  return { tls: pickTLS(options), proxy: proxy ? String(proxy) : undefined };
}

function urlOf(input: unknown): string {
  if (input instanceof Request) return input.url;
  return String(input);
}

/// The init Bun understands for the one an extension wrote for Node.
export function bunInit(input: unknown, init: Init | undefined): Init | undefined {
  const dispatcher = init?.dispatcher ?? globalDispatcher;
  const agent = typeof init?.agent === "function" ? (init.agent as (url: URL) => unknown)(new URL(urlOf(input))) : init?.agent;
  if (!agent && !dispatcher && !isFormData(init?.body)) return init;
  const settings = { ...agentSettings(agent), ...(dispatcher ? dispatchers.get(dispatcher) : undefined) };
  const translated: Init = { ...init };
  if (settings.tls && !init?.tls) translated.tls = settings.tls;
  if (settings.proxy && !init?.proxy) translated.proxy = settings.proxy;
  const body = init?.body;
  if (isFormData(body)) {
    // The form-data package sets its boundary in a header only Node's http client asks it for.
    const headers = new Headers(init?.headers);
    if (!headers.has("content-type")) headers.set("content-type", `multipart/form-data; boundary=${body.getBoundary()}`);
    translated.headers = headers;
    try {
      translated.body = body.getBuffer();
    } catch {
      // A form holding a stream cannot be read at once; it goes as it is.
    }
  }
  return translated;
}

function isFormData(body: unknown): body is { getBoundary(): string; getBuffer(): Buffer } {
  return typeof body === "object" && body !== null && typeof (body as { getBoundary?: unknown }).getBoundary === "function" && typeof (body as { getBuffer?: unknown }).getBuffer === "function";
}

export function withNodeOptions<F extends (input: never, init?: never) => Promise<unknown>>(fetch: F): F {
  const wrapped = (input: unknown, init?: Init) => fetch(input as never, bunInit(input, init) as never);
  return Object.assign(wrapped, fetch) as unknown as F;
}
