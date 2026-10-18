//
//  node.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, expect, test } from "bun:test";
import { useNodeExecPath } from "../node";

const bun = process.execPath;
afterEach(() => {
  process.execPath = bun;
});

// Bitwarden runs its CLI with PATH set to dirname(process.execPath), where a bw that is a node script needs node.
test("process.execPath is the node on the PATH when there is one, and bun otherwise", () => {
  useNodeExecPath(() => null);
  expect(process.execPath).toBe(bun);

  useNodeExecPath((name) => (name === "node" ? "/opt/homebrew/bin/node" : null));
  expect(process.execPath).toBe("/opt/homebrew/bin/node");
});
