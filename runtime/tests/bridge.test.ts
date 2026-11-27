//
//  bridge.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, describe, expect, spyOn, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import { handlePop, handlePopToRoot, handleReply, request, reserveStdout, send, setPopHandler, setPopToRootHandler, setSink } from "../bridge";
import { makeTempDir } from "./support";

afterEach(() => {
  setSink();
  setPopHandler(() => send({ type: "exit" }));
  setPopToRootHandler(() => {});
});

describe("send", () => {
  test("writes one JSON line per message to the sink", () => {
    const lines: string[] = [];
    setSink((line) => lines.push(line));
    send({ type: "hud", title: "line one\nline two" });
    send({ type: "close", skipped: undefined });
    expect(lines).toEqual(['{"type":"hud","title":"line one\\nline two"}\n', '{"type":"close"}\n']);
  });

  test("writes to stdout unless a sink is set, and again once it is reset", () => {
    const stdout = spyOn(process.stdout, "write").mockImplementation(() => true);
    try {
      send({ type: "pong" });
      setSink(() => {});
      send({ type: "ignored" });
      setSink();
      send({ type: "exit" });
      expect(stdout.mock.calls.map(([line]) => line)).toEqual(['{"type":"pong"}\n', '{"type":"exit"}\n']);
    } finally {
      stdout.mockRestore();
    }
  });

  // An extension rings the bell with process.stdout.write("\x07"). On stdout it is glued onto the next message, which the app then drops.
  test("once stdout is reserved, a raw write to it goes to stderr and messages still go to stdout", () => {
    const stdout = spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderr = spyOn(process.stderr, "write").mockImplementation(() => true);
    const release = reserveStdout();
    try {
      process.stdout.write("\x07");
      send({ type: "pong" });
      expect(stdout.mock.calls.map(([line]) => line)).toEqual(['{"type":"pong"}\n']);
      expect(stderr.mock.calls.map(([text]) => text)).toEqual(["\x07"]);
    } finally {
      release();
      stdout.mockRestore();
      stderr.mockRestore();
    }
  });

  test("the real host keeps a command's raw write out of what the app reads", async () => {
    const home = makeTempDir("home");
    const extDir = path.join(home, "extension");
    fs.mkdirSync(path.join(extDir, "src"), { recursive: true });
    fs.writeFileSync(path.join(extDir, "package.json"), JSON.stringify({ name: "bell-sample", commands: [{ name: "ring", mode: "no-view" }] }));
    fs.writeFileSync(
      path.join(extDir, "src/ring.ts"),
      'import { showHUD } from "@raycast/api";\nexport default async function Command() { process.stdout.write("\\x07ding"); await showHUD("Timer done"); }',
    );
    try {
      const proc = Bun.spawn(["bun", path.join(import.meta.dir, "../host.ts"), extDir, "ring"], {
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
        env: { ...process.env, HOME: home },
      });
      const [out, log] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
      const lines = out.split("\n").filter(Boolean);
      expect(lines.map((line) => JSON.parse(line).type)).toEqual(["hud", "exit"]);
      expect(log).toContain("\x07ding");
    } finally {
      fs.rmSync(home, { recursive: true, force: true });
    }
  });

  test("the real host takes the command's arguments from its input, as the app sends them", async () => {
    const home = makeTempDir("home");
    const extDir = path.join(home, "extension");
    fs.mkdirSync(path.join(extDir, "src"), { recursive: true });
    fs.writeFileSync(path.join(extDir, "package.json"), JSON.stringify({ name: "login-sample", commands: [{ name: "login", mode: "no-view" }] }));
    fs.writeFileSync(
      path.join(extDir, "src/login.ts"),
      'import { showHUD } from "@raycast/api";\nexport default async function Command(props) { await showHUD(props.arguments.password); }',
    );
    try {
      const proc = Bun.spawn(["bun", path.join(import.meta.dir, "../host.ts"), extDir, "login"], {
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
        env: { ...process.env, HOME: home, FLOE_SECRETS: "input" },
      });
      // Left open: the host ends on its own once a command without a view is done, and at once when its input closes.
      proc.stdin.write(JSON.stringify({ type: "secrets", arguments: JSON.stringify({ password: "hunter2" }) }) + "\n");
      proc.stdin.flush();
      const out = await new Response(proc.stdout).text();
      const hud = out.split("\n").filter(Boolean).map((line) => JSON.parse(line)).find((message) => message.type === "hud");
      expect(hud?.title).toBe("hunter2");
    } finally {
      fs.rmSync(home, { recursive: true, force: true });
    }
  });
});

describe("pop handlers", () => {
  test("the installed handlers receive the app's pop and pop-to-root", () => {
    const calls: string[] = [];
    setPopHandler(() => calls.push("pop"));
    setPopToRootHandler(() => calls.push("popToRoot"));
    handlePop();
    handlePopToRoot();
    expect(calls).toEqual(["pop", "popToRoot"]);
  });
});

describe("requests", () => {
  test("each request gets its own id, and a reply settles only the request it names", async () => {
    const messages: Record<string, any>[] = [];
    setSink((line) => messages.push(JSON.parse(line)));
    const first = request<string>("ai.ask", { prompt: "one" });
    const second = request<string>("ai.ask");
    expect(messages.map((message) => message.type)).toEqual(["request", "request"]);
    expect(messages[0].id).not.toBe(messages[1].id);
    expect(messages[1].params).toEqual({});
    handleReply({ id: messages[1].id, result: "second" });
    handleReply({ id: messages[0].id, error: "first failed" });
    expect(await second).toBe("second");
    await expect(first).rejects.toThrow("first failed");
  });

  test("a reply nobody is waiting for is ignored", () => {
    expect(() => handleReply({ id: -1, result: "stray" })).not.toThrow();
  });
});
