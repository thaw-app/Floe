//
//  native.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// An extension's swift: package, called as Raycast's extensions-swift-tools build it: the function's name and one JSON
// value per argument in, the result as JSON out. Raycast builds it with the extension; Floe on the first call.
import fs from "node:fs";
import path from "node:path";
import { ctx } from "./bridge";
import { newestChange } from "./build";
import { showToast } from "./api/index";

export class SwiftError extends Error {
  stdout: string;
  stderr: string;

  constructor(message: string, output: { stdout: string; stderr: string }) {
    super(message);
    this.name = "SwiftError";
    this.stdout = output.stdout;
    this.stderr = output.stderr;
  }
}

const builds = new Map<string, Promise<string>>();

export async function runSwiftFunction(packageDir: string, name: string, args: unknown[]): Promise<unknown> {
  let built = builds.get(packageDir);
  if (!built) {
    built = buildPackage(packageDir);
    builds.set(packageDir, built);
    // A failed build is tried again on the next call.
    built.catch(() => builds.delete(packageDir));
  }
  const binary = await built;
  // undefined has no JSON, and Swift reads a missing value as null.
  const output = await run(binary, [name, ...args.map((arg) => JSON.stringify(arg, (_key, value) => (value === undefined ? null : value)))]);
  if (output.code !== 0) throw new SwiftError(output.stderr || output.stdout || "Could not get any data", output);
  if (output.stdout.length === 0) return null;
  try {
    return JSON.parse(output.stdout);
  } catch (error) {
    throw new SwiftError(`Failed to deserialize result from JSON: ${(error as Error).message}`, output);
  }
}

type Output = { code: number | null; stdout: string; stderr: string };

async function run(command: string, args: string[]): Promise<Output> {
  const child = Bun.spawn([command, ...args], { stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, code] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
  return { code, stdout: stdout.trim(), stderr: stderr.trim() };
}

/// Builds the package once per change of its sources and answers the executable's path.
async function buildPackage(packageDir: string): Promise<string> {
  const scratch = path.join(ctx.dataPath, "swift", path.basename(packageDir));
  const stampFile = path.join(scratch, "floe-build.json");
  // SwiftPM's own folders start with a dot, which newestChange skips.
  const fingerprint = String(newestChange(packageDir));
  try {
    const stamp = JSON.parse(fs.readFileSync(stampFile, "utf8")) as { fingerprint: string; binary: string };
    if (stamp.fingerprint === fingerprint && fs.existsSync(stamp.binary)) return stamp.binary;
  } catch {}

  // The tests hand in a stand-in toolchain.
  const swift = process.env.FLOE_SWIFT ?? "swift";
  const described = await run(swift, ["package", "dump-package", "--package-path", packageDir]).catch(() => undefined);
  if (!described) throw new Error("This command needs Apple's Swift tools. Install Xcode, or run: xcode-select --install");
  if (described.code !== 0) throw new SwiftError(`Floe couldn't read this extension's Swift package: ${described.stderr}`, described);
  const targets = (JSON.parse(described.stdout) as { targets: { name: string; type: string }[] }).targets.filter((target) => target.type === "executable");
  if (targets.length !== 1) throw new Error(`The Swift package must have exactly one executable target, and ${path.basename(packageDir)} has ${targets.length}.`);

  // The first build compiles the Swift macros too, which takes minutes; later ones take seconds.
  const toast = await showToast({ style: "animated", title: "Building this extension's Swift code", message: "The first time takes a few minutes." }).catch(() => undefined);
  fs.mkdirSync(scratch, { recursive: true });
  const built = await run(swift, ["build", "-c", "release", "--package-path", packageDir, "--scratch-path", scratch]).finally(() => toast?.hide());
  if (built.code !== 0) throw new SwiftError(`Floe couldn't build this extension's Swift code:\n${built.stderr || built.stdout}`.trim(), built);
  const binary = path.join(scratch, "release", targets[0].name);
  fs.writeFileSync(stampFile, JSON.stringify({ fingerprint, binary }));
  return binary;
}
