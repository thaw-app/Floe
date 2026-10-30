//
//  survey.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Compatibility survey: bun survey.ts <dir of extensions> [seconds per command]
// Runs up to two view commands per extension headlessly; no-view commands are skipped since they act on the system.
import fs from "node:fs";
import path from "node:path";
import { oneLine } from "./lines";
import { findNodes, hostMessages, isItem, sendToHost, startHost, topView, type HostMessage, type TreeNode } from "./testing";

const [root, secondsArg] = process.argv.slice(2);
const seconds = Number(secondsArg ?? 10);

type Result = { ext: string; command: string; status: string; detail: string };
type Preference = { name: string; required?: boolean; default?: unknown };
type Observation = { view: string; items: number; loading: boolean; hasContent: boolean; error: string; probed: boolean };

const required = (preferences: Preference[] = []) =>
  preferences.filter((preference) => preference.required && preference.default === undefined).map((preference) => preference.name);

function errorFrom(message: HostMessage): string {
  if (message.type === "error") return message.message;
  if (message.type === "toast" && message.style === "failure") return `toast: ${message.title} ${message.message ?? ""}`;
  return "";
}

function observe(view: TreeNode, seen: Observation) {
  seen.view = view.type;
  seen.loading = Boolean(view.props.isLoading);
  seen.items = findNodes(view, isItem).length;
  const hasStaticContent = findNodes(view, (node) => node.type === "EmptyView" || node.type.startsWith("Form.")).length > 0;
  seen.hasContent = seen.items > 0 || Boolean(view.props.markdown) || hasStaticContent;
}

function classify(seen: Observation, stderrError: string): string {
  if (seen.view && seen.hasContent) return seen.view === "Form" ? "form" : "ok";
  // Signing in needs the app and a person, so a headless run counts it apart from a failure.
  if (/Floe can't sign in/.test(seen.error || stderrError)) return "needs-signin";
  if (seen.error) return "error";
  if (seen.view) return "empty";
  return stderrError ? "error" : "nothing";
}

async function run(ext: string, command: string): Promise<Result> {
  const proc = startHost(path.join(root, ext), command, "pipe");
  const seen: Observation = { view: "", items: 0, loading: false, hasContent: false, error: "", probed: false };
  // SIGTERM first, as the app does; a command that blocks its event loop never runs the handler, so SIGKILL follows.
  const timer = setTimeout(() => {
    proc.kill();
    setTimeout(() => proc.kill("SIGKILL"), 1000).unref();
  }, seconds * 1000);
  const stderr = new Response(proc.stderr as ReadableStream).text();

  for await (const message of hostMessages(proc.stdout)) {
    // No app answers here: a request (the browser's tabs, the clipboard) gets the error one would give with nothing to offer.
    if (message.type === "request") sendToHost(proc, { type: "reply", id: message.id, error: "Not available in a headless run" });
    seen.error ||= errorFrom(message);
    const view = message.type === "render" && message.tree ? topView(message.tree).view : undefined;
    if (!view) continue;
    observe(view, seen);
    if (seen.hasContent && !seen.loading) {
      proc.kill();
    } else if (!seen.probed && !seen.loading && seen.items === 0 && view.handlers?.includes("onSearchTextChange")) {
      // A search command is legitimately empty until someone types, so type something once.
      seen.probed = true;
      sendToHost(proc, { type: "event", id: view.id, prop: "onSearchTextChange", args: ["swift"] });
    }
  }
  clearTimeout(timer);

  const stderrError =
    (await stderr).split("\n").find((line) => /error|cannot find|not found|undefined is not/i.test(line) && !line.includes("Deprecation")) ?? "";
  const firstError = seen.error || stderrError;
  const status = classify(seen, stderrError);
  const reason = status === "ok" || status === "form" || status === "needs-signin" ? "" : firstError.trim().slice(0, 140);
  const detail = `${seen.view || "-"} items=${seen.items}${seen.loading ? " loading" : ""}${seen.probed ? " (after typing)" : ""} ${reason}`;
  return { ext, command, status, detail };
}

const jobs: (() => Promise<Result>)[] = [];
const results: Result[] = [];
let noView = 0;
for (const ext of fs.readdirSync(root).sort((a, b) => a.localeCompare(b))) {
  const file = path.join(root, ext, "package.json");
  if (!fs.existsSync(file)) continue;
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
  const commands: { name: string; mode?: string; preferences?: Preference[]; arguments?: Preference[] }[] = manifest.commands ?? [];
  const views = commands.filter((candidate) => (candidate.mode ?? "view") === "view");
  noView += commands.length - views.length;
  for (const command of views.slice(0, 2)) {
    const needs = [...required(manifest.preferences), ...required(command.preferences)];
    // The app asks for required arguments before it starts a command, which a headless run can't answer.
    const asks = (command.arguments ?? []).filter((argument) => argument.required).map((argument) => argument.name);
    if (needs.length > 0) results.push({ ext, command: command.name, status: "needs-prefs", detail: needs.join(", ") });
    else if (asks.length > 0) results.push({ ext, command: command.name, status: "needs-args", detail: asks.join(", ") });
    else jobs.push(() => run(ext, command.name));
  }
}

// Four workers, each taking the next job until none are left.
async function worker(): Promise<void> {
  const job = jobs.shift();
  if (!job) return;
  results.push(await job());
  return worker();
}
await Promise.all(Array.from({ length: 4 }, worker));

results.sort((a, b) => a.status.localeCompare(b.status) || a.ext.localeCompare(b.ext));
const counts: Record<string, number> = {};
for (const result of results) {
  // The folder, the command's name and the detail come from extensions, so each stays on its line.
  console.log(`${result.status.padEnd(11)} ${oneLine(result.ext + "/" + result.command).padEnd(46)} ${oneLine(result.detail)}`);
  counts[result.status] = (counts[result.status] ?? 0) + 1;
}
console.log("\nTOTAL", results.length, JSON.stringify(counts), `(no-view commands not run: ${noView})`);
