//
//  cache.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// The extension Cache: an LRU byte budget over string values, persisted per namespace. Capacity is
// per instance, so several caches or namespaces can consume several budgets at once.

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
};

/// Every namespace's snapshot, in a folder of its own: an extension may delete Cache.storageDirectory outright.
function cacheDirectory(): string {
    const directory = path.join(ctx.dataPath, "cache");
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
            evicted.push([oldestKey, undefined]);
        }
        this.entries.set(key, value);
        this.used += cost;
        this.persist([...evicted, [key, value]]);
    };

    readonly remove = (key: string) => {
        const stale = this.entries.get(key);
        if (stale === undefined) return false;
        this.used -= Buffer.byteLength(key, "utf8") + Buffer.byteLength(stale, "utf8");
        this.entries.delete(key);
        this.persist([[key, undefined]]);
        return true;
    };

    readonly clear = (options?: { notifySubscribers?: boolean }) => {
        this.entries.clear();
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
        const snapshot: Snapshot = { version: 1, entries: [...this.entries] };
        try {
            cachePersistence.write(this.file, JSON.stringify(snapshot));
        } catch (error) {
            console.error(`cache ${path.basename(this.file)} was not saved:`, error);
        }
    };

    /// Legacy files were plain string dictionaries; their enumeration order becomes the initial
    /// recency. Records that do not fit the budget are dropped before they are retained.
    private restore() {
        if (this.capacity === 0) return;
        let content: string;
        try {
            if (fs.statSync(this.file).size > this.restoreCeiling()) return;
            content = fs.readFileSync(this.file, "utf8");
        } catch {
            return;
        }
        let parsed: unknown;
        try {
            parsed = JSON.parse(content);
        } catch {
            return;
        }
        for (const [key, value] of recordsOf(parsed)) {
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
