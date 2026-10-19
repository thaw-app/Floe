//
//  node.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, expect, test } from "bun:test";
import childProcess from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { useNodeExecPath } from "../node";
import { makeTempDir } from "./support";

const bun = process.execPath;
const fork = childProcess.fork;
afterEach(() => {
  process.execPath = bun;
  childProcess.fork = fork;
});

// Bitwarden runs its CLI with PATH set to dirname(process.execPath), where a bw that is a node script needs node.
test("process.execPath is the node on the PATH when there is one, and bun otherwise", () => {
  useNodeExecPath(() => null);
  expect(process.execPath).toBe(bun);

  useNodeExecPath((name) => (name === "node" ? "/opt/homebrew/bin/node" : null));
  expect(process.execPath).toBe("/opt/homebrew/bin/node");
});

// A forked child that loads the command's TypeScript would fail under node.
test("a forked child runs under bun after process.execPath names node", async () => {
  const folder = makeTempDir("fork");
  const script = path.join(folder, "child.ts");
  fs.writeFileSync(script, "process.send?.(process.versions.bun ?? 'node'); process.disconnect?.();");
  useNodeExecPath((name) => (name === "node" ? "/nonexistent/node" : null));
  const child = require("node:child_process").fork(script);
  const answer = await new Promise((resolve) => child.once("message", resolve));
  expect(answer).toBe(Bun.version);
  fs.rmSync(folder, { recursive: true, force: true });
});
