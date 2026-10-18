//
//  build.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Finds a command's entry file and bundles it for the host. Reads the extension and command from ctx,
// which host.ts fills in before calling.
import fs from "node:fs";
import path from "node:path";
import { ctx } from "./bridge";

// Bundle the command so that @raycast/api points at our shim and React at the host's copy,
// whatever the extension's node_modules holds. Both stay external so there is one instance of each.
export const shimPath = path.join(import.meta.dir, "api/index.ts");
// Raycast builds every command to CommonJS, where a name a module does not export is undefined and not a failed
// import. A command with a top-level await cannot be CommonJS, so that one is built as a module.
const formats = ["cjs", "esm"] as const;
export async function bundle(entry: string): Promise<string> {
  const outdir = path.join(ctx.dataPath, "build");
  const output = path.join(outdir, `${ctx.commandName}.js`);
  const stamp = path.join(outdir, `${ctx.commandName}.fingerprint`);
  const current = fingerprint(entry);
  if (fs.existsSync(output) && readText(stamp) === current) return output;

  const started = performance.now();
  const result = await build(entry, outdir);
  if (!result.success) throw new Error(result.logs.map(String).join("\n"));
  useCompatModules(output);
  fs.writeFileSync(stamp, current);
  // host.ts points console at stderr, so this never lands on the protocol stream.
  console.error(`bundled ${ctx.manifest.name}/${ctx.commandName} in ${Math.round(performance.now() - started)} ms`);
  return output;
}

// Bun builds these names to its own modules whatever the extension installed, and calls no plugin for them, so the
// finished bundle is pointed at Floe's stand-ins, which take the Node options Bun's ignore.
const compatDir = path.join(import.meta.dir, "compat");
function useCompatModules(output: string) {
  const code = fs.readFileSync(output, "utf8");
  const pointed = code.replace(/(require\(|from\s*)"(node-fetch|undici|ws)"/g, (_match, lead: string, name: string) =>
    `${lead}${JSON.stringify(path.join(compatDir, `${name}.ts`))}`,
  );
  if (pointed !== code) fs.writeFileSync(output, pointed);
}

function readText(file: string): string | undefined {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return undefined;
  }
}

// Newest modification time under a source tree, skipping dependencies and build output.
export function newestChange(target: string): number {
  const stat = fs.statSync(target, { throwIfNoEntry: false });
  if (!stat) return 0;
  if (!stat.isDirectory()) return stat.mtimeMs;
  let newest = stat.mtimeMs;
  for (const entry of fs.readdirSync(target, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name.startsWith(".")) continue;
    newest = Math.max(newest, newestChange(path.join(target, entry.name)));
  }
  return newest;
}

// A cached bundle is reused while the sources, manifest, dependencies, runtime location and Bun are unchanged.
// The shim and React paths are baked into the bundle, so a moved app invalidates it too.
export function fingerprint(entry: string): string {
  const sources = path.join(ctx.extDir, "src");
  return JSON.stringify({
    entry,
    sources: newestChange(entry.startsWith(sources + path.sep) ? sources : entry),
    manifest: newestChange(path.join(ctx.extDir, "package.json")),
    dependencies: newestChange(path.join(ctx.extDir, "node_modules", ".package-lock.json")) || newestChange(path.join(ctx.extDir, "bun.lock")),
    // What __dirname is defined as, so a bundle built before it was is built again.
    root: ctx.extDir,
    formats,
    shim: shimPath,
    shimChanged: newestChange(path.join(import.meta.dir, "api")),
    compat: newestChange(compatDir),
    react: require.resolve("react"),
    bun: Bun.version,
  });
}

async function build(entry: string, outdir: string) {
  try {
    return await buildUnchecked(entry, outdir, "cjs");
  } catch {
    return buildAs(entry, outdir, "esm");
  }
}

async function buildAs(entry: string, outdir: string, format: (typeof formats)[number]) {
  try {
    return await buildUnchecked(entry, outdir, format);
  } catch (error) {
    // Bun throws an AggregateError whose useful text is in the individual build messages.
    const messages = (error as AggregateError).errors?.map(String).join("\n");
    throw new Error(messages || String(error));
  }
}

function buildUnchecked(entry: string, outdir: string, format: (typeof formats)[number]) {
  return Bun.build({
    entrypoints: [entry],
    outdir,
    target: "bun",
    format,
    naming: `${ctx.commandName}.js`,
    // Raycast's own build leaves one file per command at the extension's root, and extensions find their
    // assets from there. Bun would put each source file's own folder in its place.
    define: {
      __dirname: JSON.stringify(ctx.extDir),
      __filename: JSON.stringify(path.join(ctx.extDir, `${ctx.commandName}.js`)),
    },
    plugins: [
      {
        name: "raycast-shim",
        setup(build) {
          build.onResolve({ filter: /^@raycast\/api$/ }, () => ({ path: shimPath, external: true }));
          build.onResolve({ filter: /^react(\/jsx-runtime|\/jsx-dev-runtime)?$/ }, (args) => ({
            path: require.resolve(args.path),
            external: true,
          }));
          // An imported .wasm file is its compiled module, which is what extensions hand to WebAssembly.instantiate.
          // Bun would give the file's name. "?module" is the same import as other bundlers want it spelled.
          build.onResolve({ filter: /\.wasm\?module$/ }, (args) => ({
            path: Bun.resolveSync(args.path.slice(0, -"?module".length), path.dirname(args.importer)),
          }));
          build.onLoad({ filter: /\.wasm$/ }, (args) => ({
            loader: "js",
            contents: `import { readFileSync } from "node:fs";\nexport default new WebAssembly.Module(readFileSync(${JSON.stringify(args.path)}));`,
          }));
          // A V8 addon Bun cannot load, whichever build of it the extension installed.
          build.onResolve({ filter: /^better-sqlite3(-multiple-ciphers)?$/ }, () => ({ path: path.join(compatDir, "better-sqlite3.ts"), external: true }));
          // Each importer gets its own copy, holding the names it imports.
          build.onResolve({ filter: /^(swift|rust):/ }, (args) => ({ path: `${args.importer}|${args.path}`, namespace: "native" }));
          build.onLoad({ filter: /.*/, namespace: "native" }, (args) => {
            const [importer, specifier] = splitLast(args.path, "|");
            return { loader: "js", contents: nativeStub(specifier, readText(importer) ?? "") };
          });
        },
      },
    ],
  });
}

function splitLast(text: string, separator: string): [string, string] {
  const index = text.lastIndexOf(separator);
  return [text.slice(0, index), text.slice(index + separator.length)];
}

// Raycast compiles an extension's swift: or rust: package into a helper Floe cannot build yet. The import
// still builds, so commands that never call the helper (some only do on Windows) run, and a call says why it fails.
export function nativeStub(specifier: string, importerSource: string): string {
  const language = specifier.startsWith("swift:") ? "Swift" : "Rust";
  const quoted = specifier.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const imports = new RegExp(`import\\s+(?:type\\s+)?(?:[\\w$]+\\s*,\\s*)?\\{([^}]*)\\}\\s*from\\s*["']${quoted}["']`, "g");
  const names = new Set<string>();
  for (const match of importerSource.matchAll(imports)) {
    for (const part of match[1].split(",")) {
      const name = part.trim().split(/\s+as\s+/)[0];
      if (/^[\w$]+$/.test(name)) names.add(name);
    }
  }
  const unavailable = (name: string) =>
    `() => Promise.reject(new Error(${JSON.stringify(`${name} is part of this extension's ${language} code, which Floe can't build yet`)}))`;
  return [...[...names].map((name) => `export const ${name} = ${unavailable(name)};`), `export default {};`].join("\n");
}

export function findEntry(): string {
  const candidates = [
    ...[".tsx", ".ts", ".jsx", ".js"].flatMap((extension) => [
      path.join(ctx.extDir, "src", ctx.commandName + extension),
      path.join(ctx.extDir, "src", ctx.commandName, "index" + extension),
    ]),
    // Extensions installed by Raycast ship one prebuilt CommonJS bundle per command, no src/.
    path.join(ctx.extDir, ctx.commandName + ".js"),
  ];
  const entry = candidates.find((candidate) => fs.existsSync(candidate));
  if (!entry) throw new Error(`no entry file for command "${ctx.commandName}"`);
  return entry;
}
