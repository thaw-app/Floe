//
//  cache-writer.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// One process of an extension caching keys of its own, each write on its own, for the test that runs several at once.
// Usage: bun cache-writer.ts <dataPath> <prefix> <count>
import { ctx } from "../bridge";
import { Cache, flushCaches } from "../cache";

const [dataPath, prefix, count] = process.argv.slice(2);
ctx.dataPath = dataPath;
const cache = new Cache({ namespace: "shared" });
for (let index = 0; index < Number(count); index += 1) {
    cache.set(`${prefix}-${index}`, String(index));
    flushCaches();
}
