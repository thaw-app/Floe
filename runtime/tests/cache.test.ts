//
//  cache.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, beforeEach, describe, expect, spyOn, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import { Cache, cachePersistence, flushCaches } from "../cache";
import { installRuntime, makeTempDir } from "./support";

const support = installRuntime("cache-tests");
// Nothing is left for the real timer to write once the temp folder is gone.
afterEach(flushCaches);

const bytes = (text: string) => Buffer.byteLength(text, "utf8");

// Snapshots are written once per burst, so the pending one is flushed before the file is read.
function entriesOf(namespace: string): [string, string][] {
    flushCaches();
    const parsed = JSON.parse(fs.readFileSync(path.join(support.dataPath, "cache", `${namespace}.json`), "utf8"));
    return parsed.entries ?? Object.entries(parsed);
}

function writeRaw(namespace: string, content: string) {
    fs.mkdirSync(path.join(support.dataPath, "cache"), { recursive: true });
    fs.writeFileSync(path.join(support.dataPath, "cache", `${namespace}.json`), content);
}

// Proton Drive deletes storageDirectory on logout, then sweeps supportPath.
test("storageDirectory is a folder holding the caches alone, outside supportPath", () => {
    const cache = new Cache({ namespace: "located" });
    cache.set("k", "v");
    flushCaches();

    expect(cache.storageDirectory).toBe(path.join(support.dataPath, "cache"));
    expect(fs.readdirSync(cache.storageDirectory)).toContain("located.json");
    expect(cache.storageDirectory.startsWith(support.supportPath)).toBe(false);
});

test("the class says where caches live and how much each one holds, as Raycast's does", () => {
    expect(Cache.DEFAULT_CAPACITY).toBe(10 * 1024 * 1024);
    expect(Cache.STORAGE_DIRECTORY_NAME).toBe("cache");
});

describe("lru", () => {
    test("get promotes, has does not", () => {
        const capacity = bytes("one") + bytes("two") + bytes("three") + bytes("four");
        const cache = new Cache({ namespace: "promote", capacity });
        cache.set("one", "two");
        cache.set("three", "four");
        expect(cache.has("one"), "has alone leaves one the oldest").toBe(true);

        cache.get("one");
        cache.set("five", "six");
        expect(cache.has("one"), "the promoted entry survives").toBe(true);
        expect(cache.has("three"), "the untouched entry is the one evicted").toBe(false);
    });

    test("an overwrite releases its old cost, a shrink frees room", () => {
        const capacity = bytes("a") + 1 + bytes("b") + 1;
        const cache = new Cache({ namespace: "overwrite", capacity });
        cache.set("a", "v");
        cache.set("b", "v");
        cache.set("b", "");
        expect(cache.has("a"), "shrinking b freed room without evicting").toBe(true);

        cache.set("c", "v");
        expect(cache.has("b")).toBe(true);
        expect(cache.has("a"), "a is the oldest once more").toBe(false);
    });

    test("the least recent survivors are deterministic", () => {
        const cache = new Cache({ namespace: "order", capacity: bytes("a") + bytes("b") + bytes("c") + 3 * bytes("v") });
        for (const key of ["a", "b", "c"]) cache.set(key, "v");
        cache.set("d", "v");
        expect(["a", "b", "c", "d"].filter((key) => cache.has(key))).toEqual(["b", "c", "d"]);
    });

    test("zero capacity stores nothing and skips the file", () => {
        const cache = new Cache({ namespace: "empty", capacity: 0 });
        cache.set("k", "v");
        expect(cache.isEmpty).toBe(true);
        expect(cache.get("k")).toBeUndefined();
        expect(fs.existsSync(path.join(support.dataPath, "cache", "empty.json"))).toBe(false);
    });

    test.each([-1, 1.5, Number.NaN, Number.POSITIVE_INFINITY, Number.MAX_SAFE_INTEGER + 1])(
        "a capacity of %p is rejected before touching the disk",
        (capacity) => {
            expect(() => new Cache({ namespace: "invalid", capacity })).toThrow(RangeError);
            expect(fs.existsSync(path.join(support.dataPath, "cache", "invalid.json"))).toBe(false);
        },
    );

    test("an oversized replacement removes only its own stale value", () => {
        const capacity = bytes("k") + bytes("big") + bytes("other") + 1;
        const cache = new Cache({ namespace: "oversize", capacity });
        cache.set("k", "big");
        cache.set("other", "!");
        cache.set("k", "way too big for this cache");
        expect(cache.has("k")).toBe(false);
        expect(cache.has("other"), "no unrelated entry was evicted to make room").toBe(true);
    });
});

describe("bytes", () => {
    test("multibyte keys and values are counted in utf8 bytes", () => {
        const emoji = "👍";
        const cache = new Cache({ namespace: "multibyte", capacity: 2 * bytes(emoji) });
        cache.set(emoji, emoji);
        expect(cache.has(emoji)).toBe(true);

        cache.set("one more byte", "x");
        expect(cache.has(emoji), "the oversized set evicts nothing").toBe(true);
        expect(cache.has("one more byte")).toBe(false);
    });

    test("an exact fit is kept and one byte over is dropped", () => {
        const exact = new Cache({ namespace: "exact", capacity: bytes("k") + bytes("value") });
        exact.set("k", "value");
        expect(exact.has("k")).toBe(true);

        const over = new Cache({ namespace: "exact-over", capacity: bytes("k") + bytes("value") });
        over.set("k", "values");
        expect(over.has("k")).toBe(false);
    });

    test("repeated insertions keep only the expected survivors", () => {
        const cache = new Cache({ namespace: "repeat", capacity: 2 * (bytes("k-9") + 1) });
        for (let index = 0; index < 10; index++) cache.set("k", String(index % 10));
        for (let index = 0; index < 10; index++) cache.set(`k-${index}`, "v");
        expect(cache.has("k"), "the refreshed entry is long gone").toBe(false);
        expect(cache.has("k-8")).toBe(true);
        expect(cache.has("k-9")).toBe(true);
        expect(cache.has("k-7")).toBe(false);
    });
});

describe("subscribers", () => {
    test("evictions and sets announce the final bounded state", () => {
        const cache = new Cache({ namespace: "notify", capacity: bytes("a") + bytes("v") + bytes("b") + bytes("v") });
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data]));
        cache.set("a", "v");
        cache.set("b", "v");
        cache.set("c", "v");
        expect(seen).toEqual([
            ["a", "v"],
            ["b", "v"],
            ["a", undefined],
            ["c", "v"],
        ]);
        expect(cache.has("b")).toBe(true);
    });

    test("an oversized set only announces the removal of what it dropped", () => {
        const cache = new Cache({ namespace: "notify-oversize", capacity: bytes("k") + bytes("kept") });
        cache.set("k", "kept");
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data]));
        cache.set("k", "much too large");
        expect(seen).toEqual([["k", undefined]]);
    });

    test("a silent clear notifies nobody and stays bounded", () => {
        const cache = new Cache({ namespace: "notify-clear", capacity: bytes("k") + bytes("v") });
        cache.set("k", "v");
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data]));
        cache.clear({ notifySubscribers: false });
        expect(seen).toEqual([]);
        expect(cache.isEmpty).toBe(true);
        expect(entriesOf("notify-clear")).toEqual([]);
    });

    test("a reentrant mutation cannot corrupt the notification pass", () => {
        const cache = new Cache({ namespace: "reentrant", capacity: bytes("first") + 1 + bytes("second") + 1 });
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => {
            seen.push([key, data]);
            if (key === "first") cache.set("second", "v");
        });
        cache.set("first", "v");
        expect(seen).toEqual([
            ["first", "v"],
            ["second", "v"],
        ]);
        expect(cache.has("second")).toBe(true);
    });
});

describe("persistence", () => {
    test("legacy dictionaries load with deterministic recency and are trimmed to the budget", () => {
        writeRaw("legacy", JSON.stringify({ alpha: "1", beta: "2", gamma: "3" }));
        const capacity = bytes("alpha") + 1 + bytes("beta") + 1;
        const cache = new Cache({ namespace: "legacy", capacity });
        expect(cache.has("alpha"), "the earliest entries fill the budget").toBe(true);
        expect(cache.has("beta")).toBe(true);
        expect(cache.has("gamma")).toBe(false);

        expect(cache.get("beta"), "the last retained entry is newest").toBe("2");
        cache.set("zeta", "4");
        expect(cache.has("beta"), "the reopened recency orders the next eviction").toBe(true);
        expect(cache.has("alpha")).toBe(false);
    });

    test("recency written by a mutation survives reopening", () => {
        const capacity = bytes("old") + 1 + bytes("new") + 2;
        const first = new Cache({ namespace: "recency", capacity });
        first.set("old", "1");
        first.set("new", "22");
        // A get alone does not rewrite the file; a mutation persists the promoted order.
        first.set("old", "1");
        const second = new Cache({ namespace: "recency", capacity });
        second.set("t3", "333");
        expect(second.has("old"), "old was rewritten newest before the reopen").toBe(true);
        expect(second.has("new"), "the unmoved entry is the one evicted").toBe(false);
        expect(second.has("t3")).toBe(true);
    });

    test("ordered numeric-looking keys keep their insertion order", () => {
        const cache = new Cache({ namespace: "numeric", capacity: 3 * (bytes("2") + 1) });
        cache.set("2", "a");
        cache.set("1", "b");
        cache.set("3", "c");
        cache.set("4", "d");
        expect(cache.has("2"), "the first-set numeric key is the oldest").toBe(false);
        expect(cache.has("1")).toBe(true);
        expect(cache.has("3")).toBe(true);
    });

    test("malformed records and corrupt files are disposable misses", () => {
        writeRaw("broken", "not json at all");
        expect(new Cache({ namespace: "broken" }).isEmpty).toBe(true);

        writeRaw("malformed", JSON.stringify({ keep: "me", drop: 42, gone: null, list: [] }));
        const cache = new Cache({ namespace: "malformed" });
        expect(cache.has("keep")).toBe(true);
        expect(cache.has("drop")).toBe(false);
        expect(cache.has("gone")).toBe(false);
        expect(cache.has("list")).toBe(false);
    });

    test("a valid snapshot reopens under a smaller capacity", () => {
        const first = new Cache({ namespace: "shrink", capacity: 3 * (bytes("one") + bytes("v")) });
        for (const key of ["one", "two", "six"]) first.set(key, "v");

        const second = new Cache({ namespace: "shrink", capacity: 2 * (bytes("one") + bytes("v")) });
        expect(second.has("one")).toBe(true);
        expect(second.has("two")).toBe(true);
        expect(second.has("six"), "restore keeps the earliest entries under a smaller budget").toBe(false);
    });

    test("an escaping-heavy valid snapshot still fits its restore ceiling", () => {
        const slashy = "\\".repeat(64);
        const capacity = 4 * (bytes("k") + bytes(slashy));
        const first = new Cache({ namespace: "escaping", capacity });
        for (const key of ["a", "b", "c", "d"]) first.set(key, slashy);

        const file = path.join(support.dataPath, "cache", "escaping.json");
        const accounted = entriesOf("escaping").reduce((total, [key, value]) => total + bytes(key) + bytes(value), 0);
        expect(fs.statSync(file).size).toBeLessThan(16 * capacity + 64 * 1024);
        expect(accounted).toBeLessThanOrEqual(capacity);

        const second = new Cache({ namespace: "escaping", capacity });
        expect(second.has("d")).toBe(true);
    });
});

describe("restore safety", () => {
    test("an over-ceiling file is rejected before it is read", () => {
        writeRaw("huge", JSON.stringify({ big: "x".repeat(4 * 1024 * 1024) }));
        const originalRead = fs.readFileSync;
        const reads: string[] = [];
        const spy = spyOn(fs, "readFileSync").mockImplementation(((file: unknown, ...rest: unknown[]) => {
            reads.push(String(file));
            return (originalRead as (...arguments_: unknown[]) => unknown)(file, ...rest);
        }) as typeof fs.readFileSync);
        try {
            const cache = new Cache({ namespace: "huge", capacity: 1024 });
            expect(cache.isEmpty).toBe(true);
            expect(reads.join()).not.toContain("cache-huge.json");
        } finally {
            spy.mockRestore();
        }
    });

    test("clear leaves an empty bounded snapshot behind", () => {
        const cache = new Cache({ namespace: "cleared", capacity: bytes("k") + bytes("v") });
        cache.set("k", "v");
        cache.clear();
        expect(entriesOf("cleared")).toEqual([]);
    });
});

describe("coalesced writes", () => {
    const original = { ...cachePersistence };
    let written: { file: string; content: string }[] = [];
    let timers: (() => void)[] = [];
    const writtenBytes = () => written.reduce((total, write) => total + bytes(write.content), 0);
    const runTimers = () => timers.splice(0).forEach((timer) => timer());

    beforeEach(() => {
        written = [];
        timers = [];
        cachePersistence.write = (file, content) => {
            written.push({ file, content });
            original.write(file, content);
        };
        cachePersistence.defer = (flush) => {
            timers.push(flush);
            return () => timers.splice(timers.indexOf(flush), 1);
        };
    });
    afterEach(() => {
        runTimers();
        Object.assign(cachePersistence, original);
    });

    test("mutations in one tick are one write of the final state", () => {
        const cache = new Cache({ namespace: "burst" });
        cache.set("a", "1");
        cache.set("b", "2");
        cache.set("a", "3");
        cache.remove("b");
        cache.set("c", "4");
        expect(written, "nothing is written while the burst runs").toEqual([]);
        expect(timers.length, "one write is scheduled for the whole burst").toBe(1);

        runTimers();
        expect(written).toHaveLength(1);
        expect(path.basename(written[0].file)).toBe("burst.json");
        expect(JSON.parse(written[0].content)).toEqual({ version: 1, entries: [["a", "3"], ["c", "4"]] });
        expect(new Cache({ namespace: "burst" }).get("c")).toBe("4");
    });

    test("a hundred 32 KiB inserts write the snapshot once, not a hundred times", () => {
        const cache = new Cache({ namespace: "amplification" });
        for (let index = 0; index < 100; index++) cache.set(`k-${index}`, "v".repeat(32 * 1024));
        runTimers();
        const finalBytes = fs.statSync(path.join(support.dataPath, "cache", "amplification.json")).size;
        expect(finalBytes).toBeGreaterThan(100 * 32 * 1024);
        expect(written).toHaveLength(1);
        expect(writtenBytes(), "writing per insert cost fifty times the final snapshot").toBe(finalBytes);
    });

    test("inserts spread over several ticks cost one write per tick", () => {
        const cache = new Cache({ namespace: "ticks" });
        for (let tick = 0; tick < 4; tick++) {
            for (let index = 0; index < 25; index++) cache.set(`k-${tick}-${index}`, "v".repeat(1024));
            runTimers();
        }
        const finalBytes = fs.statSync(path.join(support.dataPath, "cache", "ticks.json")).size;
        expect(written).toHaveLength(4);
        expect(writtenBytes()).toBeLessThan(3 * finalBytes);
    });

    test("a flush writes the pending state at once and cancels the timer", () => {
        const cache = new Cache({ namespace: "shutdown" });
        cache.set("k", "v");
        flushCaches();
        expect(written).toHaveLength(1);
        expect(JSON.parse(fs.readFileSync(path.join(support.dataPath, "cache", "shutdown.json"), "utf8")).entries).toEqual([["k", "v"]]);

        expect(timers).toHaveLength(0);
        flushCaches();
        expect(written.length, "an unchanged cache is not written again").toBe(1);
    });

    test("a mutation after a flush schedules a new write", () => {
        const cache = new Cache({ namespace: "again" });
        cache.set("k", "1");
        runTimers();
        expect(timers).toHaveLength(0);

        cache.set("k", "2");
        expect(timers).toHaveLength(1);
        runTimers();
        expect(written.map((write) => JSON.parse(write.content).entries)).toEqual([[["k", "1"]], [["k", "2"]]]);
    });

    test("reads never write, and a promotion is saved with the next mutation", () => {
        const cache = new Cache({ namespace: "reads" });
        cache.set("old", "1");
        cache.set("new", "2");
        runTimers();

        expect(cache.get("old")).toBe("1");
        expect(cache.has("new")).toBe(true);
        expect(cache.get("missing")).toBeUndefined();
        expect(cache.remove("missing")).toBe(false);
        expect(timers.length, "nothing changed, so nothing is scheduled").toBe(0);

        cache.set("third", "3");
        runTimers();
        expect(JSON.parse(written[1].content).entries.map(([key]: [string, string]) => key)).toEqual(["new", "old", "third"]);
    });

    test("subscribers hear each mutation as it happens, before anything is written", () => {
        const cache = new Cache({ namespace: "heard", capacity: 2 * (bytes("a") + bytes("v")) });
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data, written.length]));
        cache.set("a", "v");
        cache.set("b", "v");
        cache.set("c", "w");
        cache.remove("b");
        cache.clear();
        expect(seen).toEqual([
            ["a", "v", 0],
            ["b", "v", 0],
            ["a", undefined, 0],
            ["c", "w", 0],
            ["b", undefined, 0],
            [undefined, undefined, 0],
        ]);
        runTimers();
        expect(seen.length, "the write itself announces nothing").toBe(6);
    });

    test("the least recently used entry is the one evicted, in memory and on disk", () => {
        const cache = new Cache({ namespace: "evict", capacity: 3 * (bytes("a") + bytes("v")) });
        for (const key of ["a", "b", "c"]) cache.set(key, "v");
        cache.get("a");
        cache.set("d", "v");
        expect(["a", "b", "c", "d"].filter((key) => cache.has(key))).toEqual(["a", "c", "d"]);
        runTimers();
        expect(JSON.parse(written[0].content).entries).toEqual([["c", "v"], ["a", "v"], ["d", "v"]]);
    });

    test.each([
        [undefined, [[undefined, undefined]]],
        [{ notifySubscribers: true }, [[undefined, undefined]]],
        [{ notifySubscribers: false }, []],
    ])("clear(%p) empties the snapshot and notifies as asked", (options, expected) => {
        const cache = new Cache({ namespace: "clears" });
        cache.set("k", "v");
        runTimers();
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data]));
        cache.clear(options);
        expect(seen).toEqual(expected);
        expect(cache.isEmpty).toBe(true);
        runTimers();
        expect(JSON.parse(written.at(-1)!.content)).toEqual({ version: 1, entries: [] });
    });

    test("a legacy dictionary loads, and is rewritten only when something changes", () => {
        writeRaw("old-format", JSON.stringify({ alpha: "1", beta: "2" }));
        const cache = new Cache({ namespace: "old-format" });
        expect(cache.get("alpha")).toBe("1");
        expect(cache.get("beta")).toBe("2");
        expect(timers).toHaveLength(0);

        cache.set("gamma", "3");
        runTimers();
        expect(JSON.parse(written[0].content)).toEqual({ version: 1, entries: [["alpha", "1"], ["beta", "2"], ["gamma", "3"]] });
        expect(new Cache({ namespace: "old-format" }).get("alpha")).toBe("1");
    });

    test("a second instance over the same file sees what the first has not saved yet", () => {
        const first = new Cache({ namespace: "shared" });
        first.set("k", "v");
        expect(new Cache({ namespace: "shared" }).get("k")).toBe("v");
        expect(written).toHaveLength(1);
    });

    test("a failed write is logged, never thrown, and the next mutation tries again", () => {
        const cache = new Cache({ namespace: "unwritable" });
        const logged = spyOn(console, "error").mockImplementation(() => {});
        try {
            cachePersistence.write = () => {
                throw new Error("disk full");
            };
            cache.set("k", "1");
            expect(runTimers).not.toThrow();
            expect(logged).toHaveBeenCalledTimes(1);
            expect(cache.get("k"), "the value is still served from memory").toBe("1");
        } finally {
            logged.mockRestore();
        }
        cachePersistence.write = (file, content) => written.push({ file, content });
        cache.set("k", "2");
        runTimers();
        expect(JSON.parse(written[0].content).entries).toEqual([["k", "2"]]);
    });
});

// The real host and its real timer, in a throwaway home folder: each stop arrives before the timer can fire.
describe("host shutdown", () => {
    const hostPath = path.join(import.meta.dir, "../host.ts");

    function makeHost(command: string, mode: string, source: string) {
        const home = makeTempDir("home");
        const extDir = path.join(home, "extension");
        fs.mkdirSync(path.join(extDir, "src"), { recursive: true });
        fs.writeFileSync(path.join(extDir, "package.json"), JSON.stringify({ name: "flush-sample", commands: [{ name: command, mode }] }));
        fs.writeFileSync(path.join(extDir, `src/${command}.tsx`), source);
        const proc = Bun.spawn(["bun", hostPath, extDir, command], {
            stdin: "pipe",
            stdout: "pipe",
            stderr: "pipe",
            env: { ...process.env, HOME: home },
        });
        const saved = () => {
            const file = path.join(home, "Library/Application Support/Floe/Data/flush-sample/cache/default.json");
            const entries = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")).entries : undefined;
            fs.rmSync(home, { recursive: true, force: true });
            return entries;
        };
        return { proc, saved };
    }

    async function waitFor(stream: ReadableStream<Uint8Array>, marker: string) {
        const decoder = new TextDecoder();
        let text = "";
        for await (const chunk of stream) {
            text += decoder.decode(chunk);
            if (text.includes(marker)) return;
        }
        throw new Error(`the host ended before printing ${marker}`);
    }

    const view = `import { Cache, Detail } from "@raycast/api";
new Cache().set("k", "v");
console.log("ready");
export default function Command() { return <Detail markdown="" />; }`;

    test.each(["SIGTERM", "SIGINT", "SIGHUP"] as const)("%s saves the pending cache and still ends the host", async (signal) => {
        const { proc, saved } = makeHost("view", "view", view);
        await waitFor(proc.stderr, "ready");
        proc.kill(signal);
        await proc.exited;
        expect(proc.signalCode).toBe(signal);
        expect(saved()).toEqual([["k", "v"]]);
    });

    test("the app closing the host's input saves the pending cache", async () => {
        const { proc, saved } = makeHost("view", "view", view);
        await waitFor(proc.stderr, "ready");
        proc.stdin.end();
        expect(await proc.exited).toBe(0);
        expect(saved()).toEqual([["k", "v"]]);
    });

    test("a no-view command's cache is on disk before the app hears exit", async () => {
        // Set after the command returns, so the write is still pending when the host's own exit timer runs.
        const source = `import { Cache } from "@raycast/api";
export default async function Command() { setTimeout(() => new Cache().set("k", "v"), 30); }`;
        const { proc, saved } = makeHost("once", "no-view", source);
        await waitFor(proc.stdout, '"exit"');
        proc.kill("SIGKILL");
        await proc.exited;
        expect(saved()).toEqual([["k", "v"]]);
    });

    test("closeMainWindow saves first, because a background run is killed on it", async () => {
        const source = `import { Cache, closeMainWindow } from "@raycast/api";
export default async function Command() {
  new Cache().set("k", "v");
  await closeMainWindow();
  await new Promise((resolve) => setTimeout(resolve, 5000));
}`;
        const { proc, saved } = makeHost("closer", "no-view", source);
        await waitFor(proc.stdout, '"close"');
        proc.kill("SIGKILL");
        await proc.exited;
        expect(saved()).toEqual([["k", "v"]]);
    });
});
