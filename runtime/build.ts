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
import { pathToFileURL } from "node:url";
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
  } catch (error) {
    const retry = retryFor(error);
    return buildAs(entry, outdir, retry.entities || retry.preferMain || retry.unresolved ? "cjs" : "esm", retry);
  }
}

// What stopped the first build that Raycast's esbuild goes past. Anything else is retried as a module, for a
// command with a top-level await.
function retryFor(error: unknown): Retry {
  const message = describe(error);
  // A dependency's import of something that isn't installed, such as got's of electron or an optional peer, sits in
  // code that never runs here. It builds as an empty module: nothing is looked up, or fetched, when the command runs.
  const unresolved = ((error as AggregateError).errors ?? [])
    .filter((item) => item?.name === "ResolveMessage" && String(item.position?.file).includes("/node_modules/"))
    .map((item) => `${item.position.file}\0${item.specifier}`);
  return {
    entities: message.includes("Invalid JSX entity escape"),
    preferMain: /No matching export in .* for import "default"/.test(message),
    unresolved: unresolved.length > 0 ? new Set(unresolved) : undefined,
  };
}

// Bun throws an AggregateError whose useful text is in the individual build messages.
function describe(error: unknown): string {
  return (error as AggregateError).errors?.map(String).join("\n") || String(error);
}

// What a second build does differently, after the first stopped where Raycast's esbuild would have gone on.
type Retry = { entities?: boolean; preferMain?: boolean; unresolved?: Set<string> };

async function buildAs(entry: string, outdir: string, format: (typeof formats)[number], retry: Retry = {}) {
  try {
    return await buildUnchecked(entry, outdir, format, retry);
  } catch (error) {
    throw new Error(describe(error));
  }
}

// esbuild, which Raycast builds with, keeps an entity it can't read as plain text, as Converter's placeholder="&#xXXXX;";
// Bun stops. Only attribute values written name="…" are touched, since the same letters in code are code.
export function escapeUnreadableEntities(source: string): string {
  return source.replace(/(\s[\w:-]+=")([^"]*)"/g, (_match, lead: string, value: string) =>
    `${lead}${value.replace(/&#(?!(?:x[0-9a-fA-F]+|[0-9]+);)/g, "&amp;#")}"`,
  );
}

// Raycast builds for Node, which takes a package's CommonJS main over its module build; a default import of a
// package whose module build has none only works there. Packages with an exports map say for themselves.
function commonJSMain(specifier: string, importer: string): string | undefined {
  try {
    const manifestPath = Bun.resolveSync(`${specifier}/package.json`, path.dirname(importer));
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    if (manifest.exports || !manifest.main || !manifest.module) return undefined;
    return Bun.resolveSync(`./${manifest.main}`, path.dirname(manifestPath));
  } catch {
    return undefined;
  }
}

// The members extensions read, for the same file __filename names; Vite's env is not there, as under Node.
function importMeta(): Record<string, string> {
  const file = path.join(ctx.extDir, `${ctx.commandName}.js`);
  return {
    "import.meta.env": "undefined",
    "import.meta.url": JSON.stringify(pathToFileURL(file).href),
    "import.meta.filename": JSON.stringify(file),
    "import.meta.dirname": JSON.stringify(ctx.extDir),
    // A function, which define cannot hold, so the banner below declares it; Jev's PDF library resolves its worker.
    "import.meta.resolve": "__floeImportMetaResolve",
  };
}

// Resolves from the extension's folder, where its node_modules are, as a module there would.
function importMetaResolveBanner(): string {
  return `var __floeImportMetaResolve = (specifier) => require("node:url").pathToFileURL(Bun.resolveSync(specifier, ${JSON.stringify(ctx.extDir)})).href;`;
}

function buildUnchecked(entry: string, outdir: string, format: (typeof formats)[number], retry: Retry = {}) {
  return Bun.build({
    entrypoints: [entry],
    outdir,
    target: "bun",
    format,
    naming: `${ctx.commandName}.js`,
    banner: format === "cjs" ? importMetaResolveBanner() : undefined,
    // Raycast's own build leaves one file per command at the extension's root, and extensions find their
    // assets from there. Bun would put each source file's own folder in its place.
    define: {
      __dirname: JSON.stringify(ctx.extDir),
      __filename: JSON.stringify(path.join(ctx.extDir, `${ctx.commandName}.js`)),
      // CommonJS has no import.meta, so a module build that reads it (zustand's import.meta.env) would not even load.
      ...(format === "cjs" ? importMeta() : {}),
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
          if (retry.unresolved) {
            const unresolved = retry.unresolved;
            build.onResolve({ filter: /.*/ }, (args) => (unresolved.has(`${args.importer}\0${args.path}`) ? { path: args.path, namespace: "missing" } : undefined));
            build.onLoad({ filter: /.*/, namespace: "missing" }, () => ({ loader: "js", contents: "module.exports = {};" }));
          }
          if (retry.preferMain) {
            build.onResolve({ filter: /^(@[^/]+\/)?[^./@][^/]*$/ }, (args) => {
              const main = commonJSMain(args.path, args.importer);
              return main ? { path: main } : undefined;
            });
          }
          if (retry.entities) {
            build.onLoad({ filter: /\.[jt]sx$/ }, (args) =>
              args.path.includes("/node_modules/")
                ? undefined
                : { loader: args.path.endsWith(".tsx") ? "tsx" : "jsx", contents: escapeUnreadableEntities(fs.readFileSync(args.path, "utf8")) },
            );
          }
          build.onResolve({ filter: /^react-dom$/ }, () => ({ path: path.join(compatDir, "react-dom.ts"), external: true }));
          // A V8 addon Bun cannot load, whichever build of it the extension installed.
          build.onResolve({ filter: /^better-sqlite3(-multiple-ciphers)?$/ }, () => ({ path: path.join(compatDir, "better-sqlite3.ts"), external: true }));
          // Outside the bundle, like the shim, so the toast it shows while building is the shim's own.
          build.onResolve({ filter: /^floe:native$/ }, () => ({ path: path.join(import.meta.dir, "native.ts"), external: true }));
          // Each importer gets its own copy, holding the names it imports.
          build.onResolve({ filter: /^(swift|rust):/ }, (args) => ({ path: `${args.importer}|${args.path}`, namespace: "native" }));
          build.onLoad({ filter: /.*/, namespace: "native" }, (args) => {
            const [importer, specifier] = splitLast(args.path, "|");
            return { loader: "js", contents: nativeStub(specifier, importer, readText(importer) ?? "") };
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

// An extension's swift: package is built on the first call and run per call (native.ts). Raycast builds rust: code
// for Windows alone and its macOS stub rejects every call, so commands that call it only on Windows run here too.
export function nativeStub(specifier: string, importer: string, importerSource: string): string {
  const quoted = specifier.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const imports = new RegExp(`import\\s+(?:type\\s+)?(?:[\\w$]+\\s*,\\s*)?\\{([^}]*)\\}\\s*from\\s*["']${quoted}["']`, "g");
  const names = new Set<string>();
  for (const match of importerSource.matchAll(imports)) {
    for (const part of match[1].split(",")) {
      const name = part.trim().split(/\s+as\s+/)[0];
      if (/^[\w$]+$/.test(name)) names.add(name);
    }
  }
  if (specifier.startsWith("rust:")) {
    const rejected = `() => Promise.reject(new Error("Rust functions are not supported on macOS"))`;
    return [...[...names].map((name) => `export const ${name} = ${rejected};`), "export default {};"].join("\n");
  }
  const packageDir = path.resolve(path.dirname(importer), specifier.slice("swift:".length));
  const call = (name: string) => `export const ${name} = (...args) => runSwiftFunction(${JSON.stringify(packageDir)}, ${JSON.stringify(name)}, args);`;
  return ['import { runSwiftFunction } from "floe:native";', ...[...names].map(call), "export default {};"].join("\n");
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
