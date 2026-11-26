//
//  cache.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// The extension Cache: an LRU byte budget over string values, persisted per namespace. Capacity is
// per instance, so several caches or namespaces can consume several budgets at once.

import { dlopen, FFIType } from "bun:ffi";
import fs from "node:fs";
import path from "node:path";
import { ctx } from "./bridge";

type CacheSubscriber = (key: string | undefined, data: string | undefined) => void;

// Upstream Raycast documents "10 MB" without units; Floe's choice is 10 MiB.
const defaultCapacity = 10 * 1024 * 1024;

// A persisted snapshot is JSON, so escaping can inflate it well past its accounted bytes; 16× plus a
// fixed pad absorbs that without admitting arbitrary files. A safety ceiling, not an RSS guarantee.
const restoreOverheadFactor = 16;
const restorePadding = 64 * 1024;

type Snapshot = { version: 1; entries: [string, string][] };

// A burst of mutations is one write, this long after the first: writing per mutation rewrote the whole
// snapshot every time. A hard kill loses at most this window; the app allows a second for an orderly stop.
const writeDelay = 50;

/// Where and when snapshots are written. The tests swap both, to count writes and run the timer by hand.
export const cachePersistence = {
    /// The temporary file is renamed over the snapshot, so a kill mid-write keeps the previous complete one.
    write(file: string, content: string) {
        // The name carries the pid: two processes of one extension must not share a temporary file.
        const temporary = `${file}.${process.pid}.tmp`;
        fs.writeFileSync(temporary, content);
        fs.renameSync(temporary, file);
    },
    /// Returns what cancels the timer, for a flush that comes first.
    defer(flush: () => void): () => void {
        const timer = setTimeout(flush, writeDelay);
        return () => clearTimeout(timer);
    },
    /// How long a write waits for another process to let go of the snapshot before it tries again later.
    lockWait: 1000,
};

/// flock(2), from the system library. The system lets go of a lock when the process holding it ends, so a command that
/// was killed never leaves one behind. Nil where it cannot be loaded: the snapshot is then written without one.
let systemLock: ((descriptor: number, operation: number) => number) | null | undefined;
const lockExclusive = 2;
const lockWithoutWaiting = 4;

function flock(): ((descriptor: number, operation: number) => number) | null {
    if (systemLock === undefined) {
        try {
            const library = dlopen("/usr/lib/libSystem.B.dylib", { flock: { args: [FFIType.i32, FFIType.i32], returns: FFIType.i32 } });
            systemLock = (descriptor, operation) => library.symbols.flock(descriptor, operation);
        } catch {
            systemLock = null;
        }
    }
    return systemLock;
}

/// Runs work holding the lock on the snapshot's lock file, so two processes of one extension never write over each
/// other's changes. False, with nothing run, when another process held it for all of cachePersistence.lockWait.
function whileLocked(file: string, work: () => void): boolean {
    const lock = flock();
    if (!lock) {
        work();
        return true;
    }
    // Closing the file lets go of the lock. The file itself stays: removing it would let a second lock start on a new one.
    const descriptor = fs.openSync(`${file}.lock`, "a");
    try {
        const deadline = Date.now() + cachePersistence.lockWait;
        while (lock(descriptor, lockExclusive | lockWithoutWaiting) !== 0) {
            if (Date.now() > deadline) return false;
            Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2);
        }
        work();
        return true;
    } finally {
        fs.closeSync(descriptor);
    }
}

/// Every namespace's snapshot, in a folder of its own: an extension may delete Cache.storageDirectory outright.
function cacheDirectory(): string {
    const directory = path.join(ctx.dataPath, Cache.STORAGE_DIRECTORY_NAME);
    fs.mkdirSync(directory, { recursive: true });
    return directory;
}

const pending = new Set<() => void>();
let cancelDeferred: (() => void) | undefined;

/// Writes every cache with unsaved changes, now. It is synchronous so the host can call it on its way out.
export function flushCaches() {
    cancelDeferred?.();
    cancelDeferred = undefined;
    const writes = [...pending];
    pending.clear();
    for (const write of writes) write();
}

function recordsOf(parsed: unknown): [string, string][] {
    if (parsed !== null && typeof parsed === "object" && Array.isArray((parsed as Snapshot).entries)) {
        return ((parsed as Snapshot).entries as unknown[]).filter(
            (record): record is [string, string] =>
                Array.isArray(record) && record.length === 2 && typeof record[0] === "string" && typeof record[1] === "string",
        );
    }
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return [];
    return Object.entries(parsed).filter(([, value]) => typeof value === "string");
}

export class Cache {
    private readonly file: string;
    private readonly capacity: number;
    /// Oldest to newest; iteration order is the eviction and persistence order.
    private readonly entries = new Map<string, string>();
    private used = 0;
    private readonly subscribers = new Set<CacheSubscriber>();
    /// The keys this instance set or removed since it last wrote, and whether it cleared everything. Only these are
    /// its to write: other keys in the snapshot may have been changed meanwhile by another instance or process.
    private readonly changed = new Set<string>();
    private cleared = false;
    /// The snapshot as this instance last read or wrote it. While the file is still that one, nobody else wrote, and
    /// it is not read again: reading a full snapshot at every write would cost its size in memory each time.
    private seen: string | undefined;

    constructor(options?: { namespace?: string; capacity?: number }) {
        const requested = options?.capacity ?? defaultCapacity;
        if (!Number.isInteger(requested) || requested < 0 || requested > Number.MAX_SAFE_INTEGER) {
            throw new RangeError(`cache capacity must be a nonnegative integer, got ${String(options?.capacity)}`);
        }
        this.capacity = requested;
        this.file = path.join(cacheDirectory(), `${options?.namespace ?? "default"}.json`);
        // Another instance over the same file may have changes that are not on disk yet.
        flushCaches();
        this.restore();
    }

    // Raycast's own: the folder the caches live in, under the data folder, and the size each one gets.
    static get STORAGE_DIRECTORY_NAME() {
        return "cache";
    }

    static get DEFAULT_CAPACITY() {
        return defaultCapacity;
    }

    get storageDirectory() {
        return path.dirname(this.file);
    }

    get isEmpty() {
        return this.entries.size === 0;
    }

    readonly get = (key: string) => {
        const value = this.entries.get(key);
        if (value === undefined) return undefined;
        this.entries.delete(key);
        this.entries.set(key, value);
        return value;
    };

    readonly has = (key: string) => this.entries.has(key);

    readonly set = (key: string, value: string) => {
        const keyBytes = Buffer.byteLength(key, "utf8");
        const cost = keyBytes + Buffer.byteLength(value, "utf8");
        if (cost > this.capacity) {
            // Nothing fits, so no unrelated entry is evicted to make room; a stale value for this key
            // goes, and observers hear a removal rather than a value that was never kept.
            const stale = this.entries.get(key);
            if (stale !== undefined) {
                this.used -= keyBytes + Buffer.byteLength(stale, "utf8");
                this.entries.delete(key);
                this.changed.add(key);
                this.persist([[key, undefined]]);
            }
            return;
        }
        const stale = this.entries.get(key);
        if (stale !== undefined) {
            this.used -= keyBytes + Buffer.byteLength(stale, "utf8");
            this.entries.delete(key);
        }
        const evicted: [string, undefined][] = [];
        while (this.used + cost > this.capacity) {
            const oldestKey = this.entries.keys().next().value;
            if (oldestKey === undefined) break;
            const oldestValue = this.entries.get(oldestKey)!;
            this.used -= Buffer.byteLength(oldestKey, "utf8") + Buffer.byteLength(oldestValue, "utf8");
            this.entries.delete(oldestKey);
            this.changed.add(oldestKey);
            evicted.push([oldestKey, undefined]);
        }
        this.entries.set(key, value);
        this.changed.add(key);
        this.used += cost;
        this.persist([...evicted, [key, value]]);
    };

    readonly remove = (key: string) => {
        const stale = this.entries.get(key);
        if (stale === undefined) return false;
        this.used -= Buffer.byteLength(key, "utf8") + Buffer.byteLength(stale, "utf8");
        this.entries.delete(key);
        this.changed.add(key);
        this.persist([[key, undefined]]);
        return true;
    };

    readonly clear = (options?: { notifySubscribers?: boolean }) => {
        this.entries.clear();
        this.changed.clear();
        this.cleared = true;
        this.used = 0;
        this.persist(options?.notifySubscribers === false ? [] : [[undefined, undefined]]);
    };

    readonly subscribe = (subscriber: CacheSubscriber) => {
        this.subscribers.add(subscriber);
        return () => {
            this.subscribers.delete(subscriber);
        };
    };

    /// Subscribers hear a mutation as it happens, over a frozen copy, so a callback that unsubscribes
    /// or mutates cannot corrupt the notification pass. The snapshot follows later, once per burst.
    private readonly persist = (notifications: [string | undefined, string | undefined][]) => {
        pending.add(this.write);
        cancelDeferred ??= cachePersistence.defer(flushCaches);
        const frozen = [...this.subscribers];
        for (const [key, value] of notifications) {
            frozen.forEach((subscriber) => subscriber(key, value));
        }
    };

    /// A snapshot that cannot be written is a lost cache, not a failed command: this runs from a timer
    /// or at exit, where nobody is left to catch it.
    private readonly write = () => {
        try {
            const wrote = whileLocked(this.file, () => {
                if (this.stamp() !== this.seen) this.takeOthersChanges(this.read());
                const snapshot: Snapshot = { version: 1, entries: [...this.entries] };
                cachePersistence.write(this.file, JSON.stringify(snapshot));
                this.seen = this.stamp();
            });
            if (!wrote) {
                // Written without the lock, it could undo what the other process is writing. The changes wait for the
                // next try; one still waiting when the host ends is lost, as it would be to a kill.
                pending.add(this.write);
                cancelDeferred ??= cachePersistence.defer(flushCaches);
                return;
            }
            this.changed.clear();
            this.cleared = false;
        } catch (error) {
            console.error(`cache ${path.basename(this.file)} was not saved:`, error);
        }
    };

    /// Joins what is on disk now to this instance's own changes, in this instance's order of use. A key it did not
    /// change takes the value on disk, or goes with it; a key only the disk has comes in as the least recent. Nothing
    /// from the disk survives this instance's clear. Subscribers hear nothing of it: their own instance announces it.
    private takeOthersChanges(onDisk: [string, string][]) {
        const disk = new Map(this.cleared ? [] : onDisk);
        const joined = new Map<string, string>();
        for (const [key, value] of disk) {
            if (!this.entries.has(key) && !this.changed.has(key)) joined.set(key, value);
        }
        for (const [key, value] of this.entries) {
            const current = this.changed.has(key) ? value : disk.get(key);
            if (current !== undefined) joined.set(key, current);
        }
        this.entries.clear();
        this.used = 0;
        for (const [key, value] of joined) {
            this.entries.set(key, value);
            this.used += Buffer.byteLength(key, "utf8") + Buffer.byteLength(value, "utf8");
        }
        while (this.used > this.capacity) {
            const [oldestKey, oldestValue] = this.entries.entries().next().value!;
            this.used -= Buffer.byteLength(oldestKey, "utf8") + Buffer.byteLength(oldestValue, "utf8");
            this.entries.delete(oldestKey);
        }
    }

    /// Which file is there now: each write renames a new one into place, so a write by anyone changes it.
    private stamp(): string | undefined {
        try {
            const { ino, size, mtimeNs } = fs.statSync(this.file, { bigint: true });
            return `${ino}:${size}:${mtimeNs}`;
        } catch {
            return undefined;
        }
    }

    /// The snapshot's records, oldest first; none for a file that is missing, too big or not a snapshot.
    private read(): [string, string][] {
        try {
            if (fs.statSync(this.file).size > this.restoreCeiling()) return [];
            return recordsOf(JSON.parse(fs.readFileSync(this.file, "utf8")));
        } catch {
            return [];
        }
    }

    /// Legacy files were plain string dictionaries; their enumeration order becomes the initial
    /// recency. Records that do not fit the budget are dropped before they are retained.
    private restore() {
        if (this.capacity === 0) return;
        this.seen = this.stamp();
        for (const [key, value] of this.read()) {
            const cost = Buffer.byteLength(key, "utf8") + Buffer.byteLength(value, "utf8");
            if (this.entries.has(key) || this.used + cost > this.capacity) continue;
            this.entries.set(key, value);
            this.used += cost;
        }
    }

    private restoreCeiling() {
        if (this.capacity > Number.MAX_SAFE_INTEGER / restoreOverheadFactor) return Number.MAX_SAFE_INTEGER;
        return this.capacity * restoreOverheadFactor + restorePadding;
    }
}
