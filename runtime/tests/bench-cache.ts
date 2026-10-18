//
//  bench-cache.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Standalone memory workload for the extension cache: 32 MiB of generated values go through a cache
// with a 1 MiB capacity, and process.memoryUsage() is sampled along the way. Values are created one at
// a time and never kept in the harness. Without --baseline the run also asserts the expected survivors
// and the persisted snapshot's accounted bytes; --baseline only reports, which is how the unbounded
// implementation was measured. These numbers say nothing about an extension's total RSS: allocators
// keep pages after values are released, so RSS need not fall when the cache does.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { ctx } from "../bridge";
import { Cache } from "../api";
import { flushCaches } from "../cache";

const baseline = process.argv.includes("--baseline");
const valueCount = 32;
const valueBytes = 1024 * 1024;
const capacity = 1024 * 1024;

const support = fs.mkdtempSync(path.join(os.tmpdir(), "floe-bench-cache-"));
ctx.dataPath = support;

function sample(label: string) {
    const memory = process.memoryUsage();
    const mebi = (bytes: number) => (bytes / 1024 / 1024).toFixed(1);
    console.log(
        `[cache] ${label} heapUsed=${mebi(memory.heapUsed)}MiB external=${mebi(memory.external)}MiB ` +
            `arrayBuffers=${mebi(memory.arrayBuffers)}MiB rss=${mebi(memory.rss)}MiB`,
    );
    return memory;
}

function persistedEntries(): [string, string][] {
    flushCaches();
    const file = path.join(support, "cache-bounded.json");
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    return parsed.entries ?? Object.entries(parsed);
}

function accountedBytes(entries: [string, string][]): number {
    return entries.reduce((total, [key, value]) => total + Buffer.byteLength(key, "utf8") + Buffer.byteLength(value, "utf8"), 0);
}

const cache = new Cache({ namespace: "bounded", capacity });
sample("before inserts");

for (let index = 0; index < valueCount; index++) {
    cache.set(`k-${index}`, `${"v".repeat(valueBytes - 8)}${index}`);
}
sample("after 32 MiB of inserts");

// The newest entry shrinks instead of overshooting the budget; a small entry fits beside it, then goes.
cache.set(`k-${valueCount - 1}`, "w".repeat(valueBytes - 1024));
cache.set("k-mini", "m".repeat(256));
cache.remove("k-mini");
sample("after overwrite, insert and remove");

const reopened = new Cache({ namespace: "bounded", capacity });
sample("after reconstruction from disk");

const persisted = persistedEntries();
console.log(
    `[cache] persisted entries=${persisted.length} accountedBytes=${accountedBytes(persisted)} ` +
        `fileBytes=${fs.statSync(path.join(support, "cache-bounded.json")).size} bun=${Bun.version} baseline=${baseline}`,
);

cache.clear();
flushCaches();
console.log(`[cache] after clear fileBytes=${fs.statSync(path.join(support, "cache-bounded.json")).size}`);

if (!baseline) {
    if (!reopened.has(`k-${valueCount - 1}`)) throw new Error("the newest value did not survive eviction and reopen");
    if (reopened.has("k-0")) throw new Error("the oldest value survived although it should have been evicted");
    if (reopened.has("k-mini")) throw new Error("the removed value came back");
    const written = accountedBytes(persisted);
    if (written > capacity) throw new Error(`persisted cache holds ${written} accounted bytes over the ${capacity}-byte budget`);
    if (persisted.length === 0) throw new Error("nothing was persisted although the cache holds values");
}
fs.rmSync(support, { recursive: true, force: true });
