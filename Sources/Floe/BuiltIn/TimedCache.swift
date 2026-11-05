//
//  TimedCache.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Synchronization

/// What was worked out for a key, kept for a while: the search asks at every key, and the answer costs a walk of the disk or a program run.
final nonisolated class TimedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private let kept = Mutex<[Key: (taken: Date, value: Value)]>([:])
    /// Counts the times everything was forgotten, so a value made before then is not kept after.
    private let forgotten = Mutex(0)

    /// The value for the key, made now when there is none or the one kept is older than `lifetime`.
    func value(for key: Key, lasting lifetime: TimeInterval = .infinity, now: Date = Date(), make: () -> Value) -> Value {
        if let entry = kept.withLock({ $0[key] }), now.timeIntervalSince(entry.taken) < lifetime {
            return entry.value
        }
        let value = make()
        kept.withLock { $0[key] = (now, value) }
        return value
    }

    /// The same, for a value made asynchronously, such as a program's output.
    func value(for key: Key, lasting lifetime: TimeInterval = .infinity, now: Date = Date(), waitingFor make: () async -> Value) async -> Value {
        if let value = kept(for: key, lasting: lifetime, now: now) {
            return value
        }
        let round = forgotten.withLock { $0 }
        let value = await make()
        // A cancelled wait may have made nothing, and one asked later may have finished first.
        guard !Task.isCancelled else { return value }
        forgotten.withLock { forgotten in
            kept.withLock { kept in
                if forgotten == round, kept[key].map({ $0.taken <= now }) ?? true {
                    kept[key] = (now, value)
                }
            }
        }
        return value
    }

    /// The value kept for the key, when there is one no older than `lifetime`. Nothing is made.
    func kept(for key: Key, lasting lifetime: TimeInterval = .infinity, now: Date = Date()) -> Value? {
        guard let entry = kept.withLock({ $0[key] }), now.timeIntervalSince(entry.taken) < lifetime else { return nil }
        return entry.value
    }

    func forget() {
        forgotten.withLock { forgotten in
            forgotten += 1
            kept.withLock { $0.removeAll() }
        }
    }
}
