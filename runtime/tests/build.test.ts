//
//  build.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterAll, afterEach, beforeEach, describe, expect, spyOn, test, type Mock } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import React from "react";
import { ctx } from "../bridge";
import { bundle, findEntry, fingerprint, newestChange, shimPath } from "../build";
import { find, installRuntime, makeTempDir, sent, showScreen } from "./support";

installRuntime("build-tests");
const tempDirs: string[] = [];

function write(file: string, content = "") {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

// Modification times are set by hand: two writes in the same millisecond would otherwise look unchanged.
function setModified(file: string, seconds: number) {
  fs.utimesSync(file, seconds, seconds);
}

function makeExtension(files: Record<string, string>, command = "main"): string {
  const extDir = makeTempDir("extension");
  tempDirs.push(extDir);
  write(path.join(extDir, "package.json"), JSON.stringify({ name: "sample", commands: [{ name: command }] }));
  for (const [name, content] of Object.entries(files)) write(path.join(extDir, name), content);
  ctx.extDir = extDir;
  ctx.commandName = command;
  ctx.manifest = { name: "sample" };
  // Each extension has its own support folder in the app too. Bun also remembers a folder's listing
  // once it has imported from it, so a second bundle in the same folder would not be found.
  ctx.dataPath = makeTempDir("data");
  tempDirs.push(ctx.dataPath);
  return extDir;
}

// bundle() logs each real build, which is how the tests tell a build from a cache hit.
let consoleError: Mock<typeof console.error>;
beforeEach(() => {
  consoleError = spyOn(console, "error").mockImplementation(() => {});
});
afterEach(() => {
  consoleError.mockRestore();
});
afterAll(() => {
  for (const dir of tempDirs) fs.rmSync(dir, { recursive: true, force: true });
});

describe("findEntry", () => {
  test("finds a command file in src/", () => {
    const extDir = makeExtension({ "src/main.tsx": "" });
    expect(findEntry()).toBe(path.join(extDir, "src/main.tsx"));
  });

  test("finds a command folder with an index file", () => {
    const extDir = makeExtension({ "src/main/index.ts": "" });
    expect(findEntry()).toBe(path.join(extDir, "src/main/index.ts"));
  });

  test("prefers TypeScript sources over JavaScript and over a prebuilt bundle", () => {
    const extDir = makeExtension({ "src/main.js": "", "src/main.ts": "", "main.js": "" });
    expect(findEntry()).toBe(path.join(extDir, "src/main.ts"));
  });

  test("falls back to the prebuilt bundle Raycast installs beside the manifest", () => {
    const extDir = makeExtension({ "main.js": "", "other.js": "" });
    expect(findEntry()).toBe(path.join(extDir, "main.js"));
  });

  test("throws when the command has no entry file", () => {
    makeExtension({ "src/other.tsx": "" });
    expect(() => findEntry()).toThrow('no entry file for command "main"');
  });
});

describe("newestChange", () => {
  test("is zero for a missing path and the file's own time for a file", () => {
    const extDir = makeExtension({ "src/main.ts": "" });
    setModified(path.join(extDir, "src/main.ts"), 1_700_000_000);
    expect(newestChange(path.join(extDir, "missing"))).toBe(0);
    expect(newestChange(path.join(extDir, "src/main.ts"))).toBe(1_700_000_000_000);
  });

  test("walks nested folders but skips node_modules and dot entries", () => {
    const extDir = makeExtension({
      "src/main.ts": "",
      "src/deep/er/helper.ts": "",
      "src/node_modules/dep/index.js": "",
      "src/.cache/output.js": "",
    });
    const sources = path.join(extDir, "src");
    const base = newestChange(sources);
    setModified(path.join(sources, "node_modules/dep/index.js"), base / 1000 + 500);
    setModified(path.join(sources, ".cache/output.js"), base / 1000 + 500);
    expect(newestChange(sources)).toBe(base);

    setModified(path.join(sources, "deep/er/helper.ts"), Math.floor(base / 1000) + 100);
    expect(newestChange(sources)).toBe((Math.floor(base / 1000) + 100) * 1000);
  });
});

describe("fingerprint", () => {
  test("is stable while nothing changes and records what the bundle depends on", () => {
    const extDir = makeExtension({ "src/main.ts": "" });
    const entry = path.join(extDir, "src/main.ts");
    expect(fingerprint(entry)).toBe(fingerprint(entry));
    expect(JSON.parse(fingerprint(entry))).toMatchObject({ entry, shim: shimPath, bun: Bun.version, dependencies: 0 });
  });

  test("changes when any file under src/ changes, not only the entry", () => {
    const extDir = makeExtension({ "src/main.ts": "", "src/lib/helper.ts": "" });
    const entry = path.join(extDir, "src/main.ts");
    const before = fingerprint(entry);
    setModified(path.join(extDir, "src/lib/helper.ts"), Date.now() / 1000 + 60);
    expect(fingerprint(entry)).not.toBe(before);
  });

  test("changes when the manifest or the lockfile changes", () => {
    const extDir = makeExtension({ "src/main.ts": "" });
    const entry = path.join(extDir, "src/main.ts");
    const original = fingerprint(entry);

    setModified(path.join(extDir, "package.json"), Date.now() / 1000 + 60);
    const afterManifest = fingerprint(entry);
    expect(afterManifest).not.toBe(original);

    write(path.join(extDir, "bun.lock"));
    const afterBunLock = fingerprint(entry);
    expect(afterBunLock).not.toBe(afterManifest);

    write(path.join(extDir, "node_modules/.package-lock.json"));
    setModified(path.join(extDir, "node_modules/.package-lock.json"), Date.now() / 1000 + 120);
    expect(fingerprint(entry)).not.toBe(afterBunLock);
  });

  test("tracks only the bundle itself for a prebuilt command", () => {
    const extDir = makeExtension({ "main.js": "", "src/unrelated.ts": "" });
    const entry = path.join(extDir, "main.js");
    const before = fingerprint(entry);
    setModified(path.join(extDir, "src/unrelated.ts"), Date.now() / 1000 + 60);
    expect(fingerprint(entry)).toBe(before);
    setModified(entry, Date.now() / 1000 + 60);
    expect(fingerprint(entry)).not.toBe(before);
  });
});

const commandSource = `
import { List } from "@raycast/api";
import { label } from "./label";
export default function Command() {
  return <List><List.Item title={label} /></List>;
}
`;

describe("bundle", () => {
  test("bundles a command so that @raycast/api is the shim and React is the host's copy", async () => {
    const extDir = makeExtension({ "src/hello.tsx": commandSource, "src/label.ts": 'export const label = "from the bundle";' }, "hello");
    const output = await bundle(findEntry());

    expect(output).toBe(path.join(ctx.dataPath, "build", "hello.js"));
    const code = fs.readFileSync(output, "utf8");
    expect(code).toContain(JSON.stringify(shimPath));
    expect(code).toContain("from the bundle");
    expect(code).toContain(path.dirname(require.resolve("react")));
    expect(code).not.toContain(path.join(extDir, "node_modules"));

    const Command = (await import(output)).default;
    const tree = await showScreen(React.createElement(Command));
    expect(find(tree, "List.Item").props.title).toBe("from the bundle");
  });

  // Raycast builds each command into one file at the extension's root, so that is where an extension
  // expects __dirname to be, and where it looks for its assets from a file deep in src.
  test("a source file's __dirname is the extension's folder, as in the bundle Raycast builds", async () => {
    const extDir = makeExtension(
      {
        "src/where.ts": 'import { place } from "./core/devices/place";\nexport default () => place;',
        "src/core/devices/place.ts":
          'import fs from "node:fs";\nimport path from "node:path";\nexport const place = { dir: __dirname, file: __filename, script: fs.readFileSync(path.resolve(__dirname, "assets/scripts/hello.applescript"), "utf8") };',
        "assets/scripts/hello.applescript": 'return "hello"',
      },
      "where",
    );
    const place = (await import(await bundle(findEntry()))).default();

    expect(place.dir).toBe(extDir);
    expect(place.file).toBe(path.join(extDir, "where.js"));
    expect(place.script).toBe('return "hello"');
  });

  // Raycast builds to CommonJS, where a name a module does not export is undefined. As an ES module the same
  // import stops the command before it starts: "Export named 'EventEmitter' not found in module 'node:stream'".
  test("a name only CommonJS finds on a Node module is imported, and one no module has is undefined", async () => {
    makeExtension(
      {
        "src/emit.ts":
          'import { EventEmitter } from "stream";\nimport { Readable, nothingByThisName } from "node:stream";\nexport default () => ({ heard: new EventEmitter().listenerCount("data"), readable: typeof Readable, missing: typeof nothingByThisName });',
      },
      "emit",
    );
    const command = (await import(await bundle(findEntry()))).default;

    expect(command()).toEqual({ heard: 0, readable: "function", missing: "undefined" });
  });

  test("a command with a top-level await, which CommonJS cannot hold, is still built", async () => {
    makeExtension({ "src/waits.ts": "const value = await Promise.resolve(7);\nexport default () => value;" }, "waits");
    const command = (await import(await bundle(findEntry()))).default;

    expect(command()).toBe(7);
  });

  // An extension imports a .wasm file and instantiates what it gets; some spell the import "?module".
  // Bun alone gives the file's name for the first and cannot resolve the second.
  test("an imported .wasm file is its compiled module, with or without ?module", async () => {
    const extDir = makeExtension(
      {
        "src/count.ts": `import plain from "wpkg/answer.wasm";
import marked from "wpkg/answer.wasm?module";
export default async () => {
  const instance = (await WebAssembly.instantiate(plain, {})) as unknown as WebAssembly.Instance;
  return { plain: plain instanceof WebAssembly.Module, marked: marked instanceof WebAssembly.Module, answer: (instance.exports.answer as () => number)() };
};`,
        "node_modules/wpkg/package.json": '{ "name": "wpkg", "version": "1.0.0" }',
      },
      "count",
    );
    // A module that exports answer(), which returns 42.
    const wasm = "0061736d010000000105016000017f03020100070a0106616e7377657200000a06010400412a0b";
    fs.writeFileSync(path.join(extDir, "node_modules/wpkg/answer.wasm"), Buffer.from(wasm, "hex"));
    const command = (await import(await bundle(findEntry()))).default;

    expect(await command()).toEqual({ plain: true, marked: true, answer: 42 });
  });

  // Raycast Wallpaper imports a Rust helper it only calls on Windows; Bun could not resolve the import at all.
  test("a rust: import builds, and a call rejects as Raycast's own macOS stub does", async () => {
    makeExtension(
      {
        "src/wall.ts": `import { set_wallpaper as setWindows, type Monitor } from "rust:../rust";
export default async () => ({ windows: typeof setWindows, failure: await setWindows("a", "b").catch((error: Error) => error.message) });`,
      },
      "wall",
    );
    const command = (await import(await bundle(findEntry()))).default;

    expect(await command()).toEqual({ windows: "function", failure: "Rust functions are not supported on macOS" });
  });

  // Apple Reminders, Safari and others call Swift code of their own, built with Raycast's extensions-swift-tools.
  describe("a swift: import", () => {
    // Stands in for the toolchain: it describes the package and "builds" a script that answers like a built helper.
    function fakeSwift(folder: string) {
      const helper = path.join(folder, "helper.sh");
      write(helper, `#!/bin/sh
case "$1" in
  fail) echo "nope(\\"why\\")" >&2; exit 1 ;;
  nothing) exit 0 ;;
  *) name="$1"; shift; args=$(printf '%s,' "$@"); printf '{"called":"%s","args":[%s]}' "$name" "\${args%,}" ;;
esac
`);
      const swift = path.join(folder, "swift.sh");
      write(swift, `#!/bin/sh
case "$1" in
  package) echo '{"targets":[{"name":"Helper","type":"executable"},{"name":"HelperTests","type":"test"}]}' ;;
  build)
    while [ "$#" -gt 0 ]; do [ "$1" = "--scratch-path" ] && scratch="$2"; shift; done
    mkdir -p "$scratch/release" && cp "${helper}" "$scratch/release/Helper" && echo built >> "${folder}/builds.log" ;;
esac
`);
      fs.chmodSync(helper, 0o755);
      fs.chmodSync(swift, 0o755);
      return swift;
    }

    test("builds the package once and runs a function with one JSON value per argument", async () => {
      const extDir = makeExtension(
        {
          "src/remind.ts": `import { addReminder, removeReminder, clearAll } from "swift:../swift/Reminders";
export default async () => [await addReminder({ title: "Milk", due: undefined }, 2), await removeReminder("x"), await clearAll()];`,
          "swift/Reminders/Package.swift": "",
        },
        "remind",
      );
      process.env.FLOE_SWIFT = fakeSwift(extDir);
      try {
        const command = (await import(await bundle(findEntry()))).default;

        expect(await command()).toEqual([
          { called: "addReminder", args: [{ title: "Milk", due: null }, 2] },
          { called: "removeReminder", args: ["x"] },
          { called: "clearAll", args: [] },
        ]);
        expect(fs.readFileSync(path.join(extDir, "builds.log"), "utf8")).toBe("built\n");
        expect(fs.existsSync(path.join(ctx.dataPath, "swift", "Reminders", "release", "Helper"))).toBe(true);
        const toasts = sent("toast");
        expect(toasts.at(-1)).toMatchObject({ title: "Building this extension's Swift code", hidden: true });
      } finally {
        delete process.env.FLOE_SWIFT;
      }
    });

    test("a function that throws rejects with a SwiftError carrying what Swift printed, and nothing printed is null", async () => {
      const extDir = makeExtension(
        {
          "src/fails.ts": `import { fail, nothing } from "swift:../swift/Helper";
export default async () => ({ nothing: await nothing(), error: await fail().catch((error: Error & { stderr: string }) => [error.name, error.message, error.stderr]) });`,
        },
        "fails",
      );
      process.env.FLOE_SWIFT = fakeSwift(extDir);
      try {
        const command = (await import(await bundle(findEntry()))).default;

        expect(await command()).toEqual({ nothing: null, error: ["SwiftError", 'nope("why")', 'nope("why")'] });
      } finally {
        delete process.env.FLOE_SWIFT;
      }
    });
  });

  // Bun builds these three to its own modules, which drop certificate and proxy settings written for Node.
  test("node-fetch, undici and ws are Floe's stand-ins, whatever the extension installed", async () => {
    makeExtension(
      {
        "src/net.ts": `import fetch from "node-fetch";
import { Agent } from "undici";
import WebSocket from "ws";
export default () => ({ fetch, Agent, WebSocket });`,
      },
      "net",
    );
    const parts = (await import(await bundle(findEntry()))).default();

    expect(parts.fetch).toBe(require("../compat/node-fetch.ts"));
    expect(parts.Agent).toBe(require("../compat/undici.ts").Agent);
    expect(parts.WebSocket).toBe(require("../compat/ws.ts"));
  });

  test("better-sqlite3 is bun:sqlite underneath, even with no copy of its own installed", async () => {
    makeExtension({ "src/db.ts": 'import Database from "better-sqlite3-multiple-ciphers";\nexport default () => new Database().prepare("SELECT 1 + 1 AS two").get();' }, "db");
    const command = (await import(await bundle(findEntry()))).default;

    expect(command()).toEqual({ two: 2 });
  });

  // A bundle cached from before was built as an ES module, and one of those fails only when it is imported.
  test("builds again over a bundle cached from before commands were built as CommonJS", async () => {
    makeExtension({ "src/older.ts": "export default () => 1;" }, "older");
    const output = await bundle(findEntry());
    const stamp = path.join(path.dirname(output), "older.fingerprint");
    const { formats, ...before } = JSON.parse(fs.readFileSync(stamp, "utf8"));
    expect(formats).toEqual(["cjs", "esm"]);
    fs.writeFileSync(stamp, JSON.stringify(before));
    fs.appendFileSync(output, "\n// marker");

    await bundle(findEntry());
    expect(fs.readFileSync(output, "utf8")).not.toContain("// marker");
  });

  test("reuses the cached bundle until a source file changes", async () => {
    const extDir = makeExtension({ "src/cached.ts": "export default () => 1;" }, "cached");
    const entry = findEntry();
    const builds = () => consoleError.mock.calls.filter(([line]) => String(line).startsWith("bundled sample/cached")).length;

    const output = await bundle(entry);
    expect(builds()).toBe(1);
    // A marker in the output shows whether the next call rewrote it.
    fs.appendFileSync(output, "\n// marker");
    expect(await bundle(entry)).toBe(output);
    expect(builds()).toBe(1);
    expect(fs.readFileSync(output, "utf8")).toContain("// marker");

    write(path.join(extDir, "src/cached.ts"), "export default () => 2;");
    setModified(path.join(extDir, "src/cached.ts"), Date.now() / 1000 + 60);
    await bundle(entry);
    expect(builds()).toBe(2);
    expect(fs.readFileSync(output, "utf8")).not.toContain("// marker");
  });

  // What hot reload relies on: the app restarts the command after a save and the restart must not find the old bundle.
  // The times are the file system's own here, and the save is an editor's: a new file renamed over the old one.
  test("bundles again after an ordinary save of a file the entry imports", async () => {
    const extDir = makeExtension(
      { "src/saved.ts": 'import { label } from "./lib/label";\nexport default () => label;', "src/lib/label.ts": 'export const label = "before the save";' },
      "saved",
    );
    const output = await bundle(findEntry());
    expect(fs.readFileSync(output, "utf8")).toContain("before the save");

    await Bun.sleep(20);
    write(path.join(extDir, "src/lib/label.ts.tmp"), 'export const label = "after the save";');
    fs.renameSync(path.join(extDir, "src/lib/label.ts.tmp"), path.join(extDir, "src/lib/label.ts"));
    expect(await bundle(findEntry())).toBe(output);
    const code = fs.readFileSync(output, "utf8");
    expect(code).toContain("after the save");
    expect(code).not.toContain("before the save");
  });

  test("builds again when the output is missing even though the fingerprint matches", async () => {
    makeExtension({ "src/lost.ts": "export default () => 1;" }, "lost");
    const output = await bundle(findEntry());
    fs.rmSync(output);
    expect(await bundle(findEntry())).toBe(output);
    expect(fs.existsSync(output)).toBe(true);
  });

  test("builds again when the fingerprint file is missing", async () => {
    makeExtension({ "src/unstamped.ts": "export default () => 1;" }, "unstamped");
    const output = await bundle(findEntry());
    fs.rmSync(path.join(path.dirname(output), "unstamped.fingerprint"));
    fs.appendFileSync(output, "\n// marker");
    await bundle(findEntry());
    expect(fs.readFileSync(output, "utf8")).not.toContain("// marker");
  });

  test("bundles a prebuilt CommonJS command from beside the manifest", async () => {
    makeExtension({ "legacy.js": 'module.exports = { default: () => "prebuilt" };' }, "legacy");
    const output = await bundle(findEntry());
    const module = await import(output);
    // host.ts unwraps the same shape: a CommonJS bundle arrives as { default: module.exports }.
    expect(module.default.default()).toBe("prebuilt");
  });

  test("fails with the build messages when the command does not compile", async () => {
    makeExtension({ "src/broken.ts": 'import { nothing } from "./does-not-exist";\nexport default nothing;' }, "broken");
    await expect(bundle(findEntry())).rejects.toThrow(/does-not-exist/);
    expect(fs.existsSync(path.join(ctx.dataPath, "build", "broken.fingerprint"))).toBe(false);
  });
});
