//
//  folders.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterAll, describe, expect, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import { prepareFolders } from "../folders";
import { makeTempDir } from "./support";

const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) fs.rmSync(dir, { recursive: true, force: true });
});

function dataFolder(names: string[]): string {
  const dataPath = makeTempDir("data");
  tempDirs.push(dataPath);
  for (const name of names) {
    if (name.endsWith("/")) fs.mkdirSync(path.join(dataPath, name));
    else fs.writeFileSync(path.join(dataPath, name), name);
  }
  return dataPath;
}

// Paper writes its first config only into an empty supportPath; Deep Research lists every .json in it as a topic.
describe("prepareFolders", () => {
  test("gives a new extension an empty support folder of its own", () => {
    const dataPath = dataFolder([]);
    const supportPath = prepareFolders(dataPath);

    expect(supportPath).toBe(path.join(dataPath, "support"));
    expect(fs.readdirSync(supportPath)).toEqual([]);
  });

  test("moves what the extension wrote before the split into it, and caches into their own folder", () => {
    const dataPath = dataFolder(["build/", "preferences.json", "local-storage.sqlite", "dropdown-values.json", "custom-icon-1.png", "cache-default.json", "topic.json", "downloads/"]);
    const supportPath = prepareFolders(dataPath);

    expect(fs.readdirSync(supportPath).sort()).toEqual(["downloads", "topic.json"]);
    expect(fs.readdirSync(path.join(dataPath, "cache"))).toEqual(["default.json"]);
    expect(fs.readdirSync(dataPath).sort()).toEqual(["build", "cache", "custom-icon-1.png", "dropdown-values.json", "local-storage.sqlite", "preferences.json", "support"]);
  });

  test("sorts the folder once: later files beside Floe's are left alone", () => {
    const dataPath = dataFolder([]);
    prepareFolders(dataPath);
    fs.writeFileSync(path.join(dataPath, "later.json"), "");
    prepareFolders(dataPath);

    expect(fs.existsSync(path.join(dataPath, "later.json"))).toBe(true);
  });
});
