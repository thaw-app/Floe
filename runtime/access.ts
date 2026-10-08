//
//  access.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// A record of what an extension reaches: hosts it contacts, places it reads and changes, programs it starts.
// A record and not a limit: the calls are wrapped inside this process, and code that goes round them is not seen.
import childProcess from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import os from "node:os";
import path from "node:path";

export type AccessKind = "hosts" | "reads" | "writes" | "programs";
export type AccessReport = Partial<Record<AccessKind, string[]>>;

// A path as the page shows it: its first folder under home, and one deeper inside Library, where the first says
// nothing. Undefined for the extension's own files.
export function place(file: string, own: string[], home = os.homedir()): string | undefined {
  const full = path.resolve(file);
  if (full.includes("/node_modules/") || own.some((folder) => full === folder || full.startsWith(folder + "/"))) return undefined;
  if (full === home) return "~";
  if (full.startsWith(home + "/")) {
    const parts = full.slice(home.length + 1).split("/");
    const depth = parts[0] === "Library" ? 3 : 1;
    return "~/" + parts.slice(0, depth).join("/");
  }
  return "/" + full.split("/").filter(Boolean).slice(0, 2).join("/");
}

// The host a request goes to, from whatever fetch or http.request was given.
export function hostOf(target: unknown): string | undefined {
  try {
    if (typeof target === "string") return new URL(target).host || undefined;
    if (target instanceof URL) return target.host || undefined;
    if (target && typeof target === "object") {
      const options = target as { url?: string; host?: string; hostname?: string; port?: number | string };
      if (typeof options.url === "string") return new URL(options.url).host || undefined;
      const name = options.hostname ?? options.host;
      if (typeof name === "string" && name) return options.port && !name.includes(":") ? `${name}:${options.port}` : name;
    }
  } catch {}
  return undefined;
}

// The program a command line starts: its first word, without the folder.
export function programOf(command: unknown): string | undefined {
  if (typeof command !== "string") return undefined;
  const word = command.trim().split(/\s+/)[0];
  return word ? path.basename(word) : undefined;
}

const reading = ["readFile", "readFileSync", "readdir", "readdirSync", "createReadStream", "opendir", "opendirSync"] as const;
const writing = [
  "writeFile", "writeFileSync", "appendFile", "appendFileSync", "mkdir", "mkdirSync", "rm", "rmSync", "rmdir", "rmdirSync",
  "unlink", "unlinkSync", "rename", "renameSync", "copyFile", "copyFileSync", "createWriteStream",
] as const;
const starting = ["exec", "execSync", "execFile", "execFileSync", "spawn", "spawnSync"] as const;

type Wrapped = { owner: Record<string, any>; name: string; original: unknown };

// Starts recording. `report` is given only what is new, a moment after it is first seen. The function
// returned puts everything back as it was.
export function observe(options: { own: string[]; report: (found: AccessReport) => void; delay?: number }): () => void {
  const seen: Record<AccessKind, Set<string>> = { hosts: new Set(), reads: new Set(), writes: new Set(), programs: new Set() };
  let fresh: Record<AccessKind, string[]> = { hosts: [], reads: [], writes: [], programs: [] };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const wrapped: Wrapped[] = [];

  function flush() {
    timer = undefined;
    const found: AccessReport = {};
    for (const kind of Object.keys(fresh) as AccessKind[]) if (fresh[kind].length > 0) found[kind] = fresh[kind];
    fresh = { hosts: [], reads: [], writes: [], programs: [] };
    if (Object.keys(found).length > 0) options.report(found);
  }

  function note(kind: AccessKind, value: string | undefined) {
    if (!value || seen[kind].has(value)) return;
    seen[kind].add(value);
    fresh[kind].push(value);
    timer ??= setTimeout(flush, options.delay ?? 500);
  }

  function wrap(owner: Record<string, any> | undefined, name: string, before: (...args: any[]) => void) {
    const original = owner?.[name];
    if (!owner || typeof original !== "function") return;
    const replacement = function (this: unknown, ...args: any[]) {
      // The record must never be the reason a call fails.
      try {
        before(...args);
      } catch {}
      return original.apply(this, args);
    };
    try {
      owner[name] = replacement;
      wrapped.push({ owner, name, original });
    } catch {
      // Some of Bun's own functions cannot be replaced. They go unrecorded, which the page says.
    }
  }

  const pathOf = (target: unknown) => (typeof target === "string" ? target : target instanceof URL ? target.pathname : undefined);
  const read = (target: unknown) => note("reads", pathOf(target) && place(pathOf(target)!, options.own));
  const write = (target: unknown) => note("writes", pathOf(target) && place(pathOf(target)!, options.own));

  wrap(globalThis as Record<string, any>, "fetch", (target) => note("hosts", hostOf(target)));
  for (const module of [http, https]) for (const name of ["request", "get"]) wrap(module, name, (target) => note("hosts", hostOf(target)));
  for (const owner of [fs as Record<string, any>, fs.promises as Record<string, any>]) {
    for (const name of reading) wrap(owner, name, read);
    for (const name of writing) wrap(owner, name, write);
  }
  for (const name of starting) wrap(childProcess, name, (command) => note("programs", programOf(command)));
  const bun = (globalThis as Record<string, any>).Bun as Record<string, any> | undefined;
  wrap(bun, "spawn", (command) => note("programs", programOf(Array.isArray(command) ? command[0] : command?.cmd?.[0])));
  wrap(bun, "spawnSync", (command) => note("programs", programOf(Array.isArray(command) ? command[0] : command?.cmd?.[0])));
  wrap(bun, "file", read);
  wrap(bun, "write", write);

  return () => {
    if (timer) clearTimeout(timer);
    flush();
    for (const { owner, name, original } of wrapped.reverse()) owner[name] = original;
  };
}
