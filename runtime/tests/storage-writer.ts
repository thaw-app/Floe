//
//  storage-writer.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// One process of an extension saving keys of its own, for the test that runs several at once.
// Usage: bun storage-writer.ts <file> <prefix> <count>
import { createLocalStorage } from "../local-storage";

const [file, prefix, count] = process.argv.slice(2);
const storage = createLocalStorage(() => file);
for (let index = 0; index < Number(count); index += 1) {
    await storage.setItem(`${prefix}-${index}`, index);
}
