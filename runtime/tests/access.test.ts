//
//  access.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { describe, expect, test } from "bun:test";
import childProcess from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { hostOf, observe, place, programOf, type AccessReport } from "../access";

describe("where a path is, as the page shows it", () => {
  const home = "/Users/me";
  const own = ["/Users/me/Library/Application Support/Floe/Extensions/notes", "/Users/me/Library/Application Support/Floe/Data/notes"];

  test("the first folder under home, and one deeper inside Library", () => {
    expect(place("/Users/me/Documents/taxes/2026.pdf", own, home)).toBe("~/Documents");
    expect(place("/Users/me/.ssh/id_ed25519", own, home)).toBe("~/.ssh");
    expect(place("/Users/me/notes.txt", own, home)).toBe("~/notes.txt");
    expect(place("/Users/me/Library/Application Support/Raycast/db.sqlite", own, home)).toBe("~/Library/Application Support/Raycast");
    expect(place("/Users/me", own, home)).toBe("~");
  });

  test("outside home, the first two folders", () => {
    expect(place("/usr/local/bin/git", own, home)).toBe("/usr/local");
    expect(place("/etc/hosts", own, home)).toBe("/etc/hosts");
  });

  test("the extension's own folders and its packages are not news", () => {
    expect(place(own[0] + "/assets/icon.png", own, home)).toBeUndefined();
    expect(place(own[1], own, home)).toBeUndefined();
    expect(place("/Users/me/project/node_modules/lodash/index.js", own, home)).toBeUndefined();
    expect(place(own[0] + "-other/file", own, home)).toBe("~/Library/Application Support/Floe");
  });
});

describe("what a call names", () => {
  test("the host of a request, however it was given", () => {
    expect(hostOf("https://api.github.com/repos/x")).toBe("api.github.com");
    expect(hostOf(new URL("http://localhost:3000/a"))).toBe("localhost:3000");
    expect(hostOf(new Request("https://example.com/x"))).toBe("example.com");
    expect(hostOf({ hostname: "proton.me", port: 8443 })).toBe("proton.me:8443");
    expect(hostOf({ host: "proton.me" })).toBe("proton.me");
    expect(hostOf("not a url")).toBeUndefined();
    expect(hostOf(undefined)).toBeUndefined();
  });

  test("the program of a command line, without its folder", () => {
    expect(programOf("/usr/bin/git status")).toBe("git");
    expect(programOf("  brew   upgrade")).toBe("brew");
    expect(programOf("")).toBeUndefined();
    expect(programOf(["git"])).toBeUndefined();
  });
});

describe("recording", () => {
  test("what an extension reads, changes, contacts and starts is reported once", async () => {
    const folder = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), "floe-access-"));
    const mine = path.join(folder, "own");
    fs.mkdirSync(mine);
    fs.writeFileSync(path.join(folder, "theirs.txt"), "x");
    fs.writeFileSync(path.join(mine, "own.txt"), "x");
    const server = Bun.serve({ port: 0, fetch: () => new Response("ok") });
    const port = server.port;
    const reports: AccessReport[] = [];
    const stop = observe({ own: [mine], report: (found) => reports.push(found), delay: 10 });
    try {
      fs.readFileSync(path.join(folder, "theirs.txt"));
      fs.readFileSync(path.join(folder, "theirs.txt"));
      fs.readFileSync(path.join(mine, "own.txt"));
      fs.writeFileSync(path.join(folder, "made.txt"), "y");
      await fs.promises.readFile(path.join(folder, "theirs.txt"));
      await fetch(`http://127.0.0.1:${port}/a`);
      await fetch(`http://127.0.0.1:${port}/b`);
      childProcess.execSync("/usr/bin/true");
      await Bun.sleep(40);
    } finally {
      stop();
      server.stop(true);
    }
    const where = "/" + folder.split("/").filter(Boolean).slice(0, 2).join("/");
    const all = (kind: keyof AccessReport) => reports.flatMap((found) => found[kind] ?? []);
    expect(all("reads")).toEqual([where]);
    expect(all("writes")).toEqual([where]);
    expect(all("hosts")).toEqual([`127.0.0.1:${port}`]);
    // A command line is run by a shell, which is a program started too.
    expect(all("programs")).toContain("true");
    expect(new Set(all("programs")).size).toBe(all("programs").length);
    fs.rmSync(folder, { recursive: true });
  });

  test("stopping puts every function back, and a failing record never fails the call", () => {
    const before = [fs.readFileSync, fs.writeFileSync, globalThis.fetch, childProcess.execSync];
    const stop = observe({ own: [], report: () => {}, delay: 10 });
    expect(fs.readFileSync).not.toBe(before[0]);
    expect(() => fs.readFileSync(Symbol("odd") as unknown as string)).toThrow();
    stop();
    expect([fs.readFileSync, fs.writeFileSync, globalThis.fetch, childProcess.execSync]).toEqual(before);
  });
});
