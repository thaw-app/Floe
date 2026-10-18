//
//  compat.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import fs from "node:fs";
import https from "node:https";
import path from "node:path";
import { bunInit } from "../compat/network";
import { makeTempDir } from "./support";

const fetch = require("../compat/node-fetch.ts");
const undici = require("../compat/undici.ts");
const WebSocket = require("../compat/ws.ts");

// A local server with a certificate of its own, as a self-hosted Home Assistant or GitLab has.
let secure: ReturnType<typeof Bun.serve>;
let proxy: ReturnType<typeof Bun.serve>;
let folder: string;
beforeAll(() => {
  folder = makeTempDir("tls");
  const key = path.join(folder, "key.pem");
  const cert = path.join(folder, "cert.pem");
  Bun.spawnSync(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-keyout", key, "-out", cert, "-days", "1", "-subj", "/CN=localhost"]);
  secure = Bun.serve({
    port: 0,
    tls: { key: Bun.file(key), cert: Bun.file(cert) },
    fetch: (request, server) => (server.upgrade(request) ? undefined : new Response(`secure ${request.headers.get("content-type") ?? ""}`)),
    websocket: { message() {} },
  });
  // A proxy is asked for the whole address, where a server is asked for the path alone.
  proxy = Bun.serve({ port: 0, fetch: (request) => new Response(`proxied ${request.url}`) });
});
afterAll(() => {
  secure.stop(true);
  proxy.stop(true);
  fs.rmSync(folder, { recursive: true, force: true });
});

const secureURL = () => `https://localhost:${secure.port}/`;

describe("certificate settings written for Node", () => {
  test("node-fetch takes them from an https.Agent, and from a function that returns one", async () => {
    await expect(fetch(secureURL())).rejects.toThrow();
    const agent = new https.Agent({ rejectUnauthorized: false });
    expect(await (await fetch(secureURL(), { agent })).text()).toBe("secure ");
    expect(await (await fetch(secureURL(), { agent: () => agent })).text()).toBe("secure ");
    expect(fetch.default).toBe(fetch);
    expect(typeof fetch.FetchError).toBe("function");
  });

  test("undici's fetch takes them from an Agent's connect options, and from the global dispatcher", async () => {
    const dispatcher = new undici.Agent({ connect: { rejectUnauthorized: false } });
    expect(await (await undici.fetch(secureURL(), { dispatcher })).text()).toBe("secure ");

    undici.setGlobalDispatcher(dispatcher);
    try {
      expect(await (await undici.fetch(secureURL())).text()).toBe("secure ");
    } finally {
      undici.setGlobalDispatcher(undefined);
    }
  });

  test("ws takes rejectUnauthorized as Node's ws does", async () => {
    const opened = await new Promise<boolean>((resolve) => {
      const socket = new WebSocket(`wss://localhost:${secure.port}/`, { rejectUnauthorized: false });
      socket.on("open", () => {
        socket.close();
        resolve(true);
      });
      socket.on("error", () => resolve(false));
    });
    expect(opened).toBe(true);
    expect(WebSocket.WebSocket).toBe(WebSocket);
  });
});

describe("proxies and forms written for Node", () => {
  test("a ProxyAgent sends the request through the proxy", async () => {
    const dispatcher = new undici.ProxyAgent(`http://localhost:${proxy.port}`);
    expect(await (await undici.fetch("http://example.invalid/page", { dispatcher })).text()).toBe("proxied http://example.invalid/page");
  });

  test("an agent that names a proxy, as https-proxy-agent's do, sends the request through it", () => {
    expect(bunInit("http://example.invalid/", { agent: { proxy: new URL("http://localhost:8080") } })?.proxy).toBe("http://localhost:8080/");
  });

  // Pushover posts a form-data body and never asks it for its headers.
  test("a form-data body carries its boundary in the content type", () => {
    const form = { getBoundary: () => "XYZ", getBuffer: () => Buffer.from("--XYZ--") };
    const init = bunInit("https://example.invalid/", { method: "POST", body: form as never });

    expect(new Headers(init?.headers).get("content-type")).toBe("multipart/form-data; boundary=XYZ");
    expect(String(init?.body)).toBe("--XYZ--");
  });

  test("a request with none of these is left as it was", () => {
    const init = { method: "GET" };
    expect(bunInit("https://example.invalid/", init)).toBe(init);
  });
});

// Raycast Focus Stats keeps its sessions through Drizzle's better-sqlite3 driver, which calls these.
describe("better-sqlite3 over bun:sqlite", () => {
  const Database = require("../compat/better-sqlite3.ts");

  test("prepares, binds named parameters without their prefix, and returns rows, raw rows or a column", () => {
    const db = new Database();
    db.exec("CREATE TABLE sessions (id INTEGER PRIMARY KEY, goal TEXT UNIQUE)");
    const inserted = db.prepare("INSERT INTO sessions (goal) VALUES (@goal)").run({ goal: "write" });
    db.prepare("INSERT INTO sessions (goal) VALUES (?)").run("read");

    expect(inserted).toEqual({ changes: 1, lastInsertRowid: 1 });
    expect(db.prepare("SELECT * FROM sessions ORDER BY id").all()).toEqual([{ id: 1, goal: "write" }, { id: 2, goal: "read" }]);
    expect(db.prepare("SELECT * FROM sessions ORDER BY id").raw().all()).toEqual([[1, "write"], [2, "read"]]);
    expect(db.prepare("SELECT goal FROM sessions WHERE id = ?").pluck().get(2)).toBe("read");
    expect(db.prepare("SELECT * FROM sessions WHERE id = 9").get()).toBeUndefined();
    expect(db.pragma("user_version", { simple: true })).toBe(0);
  });

  test("a broken constraint is a SqliteError with SQLite's code, and a transaction rolls back on a throw", () => {
    const db = new Database();
    db.exec("CREATE TABLE goals (name TEXT UNIQUE)");
    const add = db.prepare("INSERT INTO goals VALUES (?)");
    add.run("focus");

    let caught: unknown;
    try {
      add.run("focus");
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(Database.SqliteError);
    expect((caught as { code: string }).code).toBe("SQLITE_CONSTRAINT_UNIQUE");

    const addBoth = db.transaction(() => {
      add.run("rest");
      add.run("focus");
    });
    expect(() => addBoth()).toThrow();
    expect(db.prepare("SELECT name FROM goals").pluck().all()).toEqual(["focus"]);
  });

  // Code Saver encrypts its snippets with a key the user sets.
  test("an encryption key is refused, not ignored", () => {
    expect(() => new Database().pragma("cipher='aes256cbc'")).toThrow("Floe can't open encrypted databases");
  });
});
