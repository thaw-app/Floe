//
//  testing.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Shared by smoke.ts and survey.ts: start the host for one command and read what it sends.
import path from "node:path";

export type TreeNode = { id: number; type: string; props: Record<string, any>; handlers?: string[]; children?: TreeNode[] };
export type HostMessage = { type: string; tree?: TreeNode; [key: string]: any };

export function startHost(extensionDir: string, command: string, stderr: "inherit" | "pipe" | "ignore") {
  return Bun.spawn(["bun", "--no-install", path.join(import.meta.dir, "host.ts"), extensionDir, command], { stdin: "pipe", stdout: "pipe", stderr });
}

export function sendToHost(proc: ReturnType<typeof startHost>, message: Record<string, unknown>) {
  proc.stdin.write(JSON.stringify(message) + "\n");
  proc.stdin.flush();
}

// The host's NDJSON output as parsed messages; lines that aren't JSON are skipped.
export async function* hostMessages(stdout: ReadableStream<Uint8Array>): AsyncGenerator<HostMessage> {
  const decoder = new TextDecoder();
  let buffer = "";
  for await (const chunk of stdout) {
    buffer += decoder.decode(chunk);
    let newline = buffer.indexOf("\n");
    while (newline >= 0) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      newline = buffer.indexOf("\n");
      try {
        yield JSON.parse(line) as HostMessage;
      } catch {
        // Not a protocol line.
      }
    }
  }
}

export function findNodes(node: TreeNode, matches: (node: TreeNode) => boolean, found: TreeNode[] = []): TreeNode[] {
  if (matches(node)) found.push(node);
  for (const child of node.children ?? []) findNodes(child, matches, found);
  return found;
}

// The screen on show and the view on it (the first child that isn't a slot).
export function topView(tree: TreeNode): { top?: TreeNode; view?: TreeNode } {
  const top = tree.children?.findLast((child) => child.type === "_screen");
  return { top, view: top?.children?.find((child) => child.type !== "_slot") };
}

export const isItem = (node: TreeNode) => node.type === "List.Item" || node.type === "Grid.Item";
