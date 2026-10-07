//
//  host.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Extension host. Usage: bun host.ts <extensionDir> <commandName> [argumentsJSON]
// Loads one Raycast command, renders it with the custom reconciler, and talks NDJSON with the Swift app.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import React from "react";
import { ctx, handlePop, handlePopToRoot, handleReply, handleReplyChunk, send, type Manifest } from "./bridge";
import { dispatchEvent, render, toError } from "./renderer";
import { NavigationRoot, commandDrewItself, handleToastAction } from "./api/index";
import { bundle, findEntry } from "./build";
import { flushCaches } from "./cache";

const log = (...parts: unknown[]) =>
  process.stderr.write(parts.map((part) => (typeof part === "string" ? part : Bun.inspect(part))).join(" ") + "\n");
console.log = console.info = console.warn = console.error = console.debug = log;

const [extDir, commandName, argumentsJSON] = process.argv.slice(2);
if (!extDir || !commandName) {
  log("usage: bun host.ts <extensionDir> <commandName> [argumentsJSON]");
  process.exit(2);
}

const manifest: Manifest = JSON.parse(fs.readFileSync(path.join(extDir, "package.json"), "utf8"));
const command = manifest.commands?.find((candidate) => candidate.name === commandName);
if (!command) {
  log(`command "${commandName}" not found in ${manifest.name}`);
  process.exit(2);
}

ctx.extDir = path.resolve(extDir);
ctx.commandName = commandName;
ctx.commandMode = command.mode ?? "view";
ctx.launchType = process.env.FLOE_LAUNCH_TYPE === "background" ? "background" : "userInitiated";
ctx.manifest = manifest;
ctx.supportPath = path.join(os.homedir(), "Library/Application Support/Floe/Data", manifest.name);
fs.mkdirSync(ctx.supportPath, { recursive: true });

function fail(error: unknown, fatal = true) {
  const err = toError(error);
  log(err.stack ?? err.message);
  send({ type: "error", message: err.message, stack: err.stack, fatal });
}
process.on("uncaughtException", (error) => fail(error));
// A rejected promise is usually one failed request, not a dead command.
process.on("unhandledRejection", (error) => fail(error, false));

// Cache writes are deferred, so every orderly way out flushes them first. The app stops a host with
// SIGTERM; the signal is raised again afterwards so the host still dies of it.
process.on("exit", flushCaches);
for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"] as const) {
  process.once(signal, () => {
    flushCaches();
    process.kill(process.pid, signal);
  });
}

let buffered = "";
process.stdin.on("data", (chunk: Buffer) => {
  buffered += chunk.toString("utf8");
  let newline: number;
  while ((newline = buffered.indexOf("\n")) >= 0) {
    const line = buffered.slice(0, newline);
    buffered = buffered.slice(newline + 1);
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    if (message.type === "event") dispatchEvent(message.id, message.prop, message.args ?? []);
    else if (message.type === "pop") handlePop();
    else if (message.type === "popToRoot") handlePopToRoot();
    else if (message.type === "replyChunk") handleReplyChunk(message);
    else if (message.type === "reply") handleReply(message);
    else if (message.type === "toastAction") handleToastAction(message.id, message.which);
    // The app's watchdog: a host stuck in synchronous code cannot answer.
    else if (message.type === "ping") send({ type: "pong" });
  }
});
process.stdin.on("end", () => process.exit(0));

const launchProps = {
  launchType: ctx.launchType,
  arguments: argumentsJSON ? JSON.parse(argumentsJSON) : {},
  fallbackText: undefined,
};

try {
  const module = await import(await bundle(findEntry()));
  // A CommonJS bundle (what Raycast installs) arrives as { default: module.exports }, whose own default is the command.
  const exported = module.default;
  const Command = typeof exported === "object" && exported !== null && "default" in exported ? exported.default : exported;
  if (typeof Command !== "function" && !commandDrewItself()) throw new Error("command has no default export");
  if (typeof Command !== "function") {
    // It drew its view itself, the way commands did before they exported one. Nothing is left to mount.
  } else if (ctx.commandMode === "menu-bar") {
    // No NavigationRoot here; the process stays alive so menu item onAction events can be dispatched.
    render(React.createElement(Command, launchProps));
  } else if (ctx.commandMode === "view") {
    render(React.createElement(NavigationRoot, null, React.createElement(Command, launchProps)));
  } else {
    await Command(launchProps);
    // Give trailing HUD/toast messages a moment to flush before the process goes away.
    setTimeout(() => {
      // A background run is killed as soon as the app reads "exit".
      flushCaches();
      send({ type: "exit" });
      process.exit(0);
    }, 50);
  }
} catch (error) {
  fail(error);
}
