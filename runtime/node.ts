//
//  node.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Raycast runs commands under Node, and extensions hand process.execPath on as "node" to scripts, CLIs and helpers
// they install. A node on the login PATH takes bun's place there; without one, bun is the closest there is.
export function useNodeExecPath(which: (name: string) => string | null = Bun.which) {
  const node = which("node");
  if (node) process.execPath = node;
}
