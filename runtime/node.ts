//
//  node.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import childProcess from "node:child_process";

// Raycast runs commands under Node, and extensions hand process.execPath on as "node" to scripts, CLIs and helpers
// they install. A node on the login PATH takes bun's place there; without one, bun is the closest there is.
// A forked child still runs under bun, as the command does, since it may load the command's own TypeScript.
export function useNodeExecPath(which: (name: string) => string | null = Bun.which) {
  const node = which("node");
  if (!node) return;
  const bun = process.execPath;
  const fork = childProcess.fork;
  childProcess.fork = ((modulePath: string, args?: unknown, options?: childProcess.ForkOptions) => {
    if (!Array.isArray(args)) {
      options ??= args as childProcess.ForkOptions | undefined;
      args = [];
    }
    return fork(modulePath, args as string[], { execPath: bun, ...options });
  }) as typeof childProcess.fork;
  process.execPath = node;
}
