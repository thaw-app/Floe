//
//  SyncRecord.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One synced value, or the note that it was removed, with when and on which Mac it last changed.
nonisolated struct SyncRecord: Codable, Equatable, Sendable {
    /// JSON text. Nil marks a removal, kept so another Mac's older copy does not bring the value back.
    var value: String?
    /// Seconds since 1970, by the clock of the Mac that made the change.
    var time: TimeInterval
    var device: String

    var isRemoval: Bool {
        value == nil
    }
}

/// How two copies of the records become one. No store and no clock in here, so every case can be tested.
nonisolated enum SyncMerge {
    /// How long a removal is remembered. A Mac that was away for longer can bring a removed value back.
    static let removalLifetime: TimeInterval = 90 * 24 * 60 * 60

    struct Outcome: Equatable {
        /// Every key with the record that won.
        var merged: [String: SyncRecord] = [:]
        /// The keys whose record from the other side won: this side takes them in.
        var apply: Set<String> = []
        /// The keys the other side lacks or holds an older record of: this side sends them.
        var push: Set<String> = []
    }

    /// Two Macs' clocks differ, so "newest" is only as right as the clocks; a tie goes to the higher device id on both sides.
    static func wins(_ record: SyncRecord, over other: SyncRecord) -> Bool {
        if record.time != other.time {
            return record.time > other.time
        }
        if record.device != other.device {
            return record.device > other.device
        }
        // The same stamp on two different records should not happen; a removal first keeps the answer the same everywhere.
        if record.isRemoval != other.isRemoval {
            return record.isRemoval
        }
        return (record.value ?? "") > (other.value ?? "")
    }

    /// A key only one side holds is kept: absence is not a removal, a removal is a record.
    static func merge(local: [String: SyncRecord], remote: [String: SyncRecord]) -> Outcome {
        var outcome = Outcome(merged: local)
        for (key, theirs) in remote {
            guard let mine = local[key] else {
                outcome.merged[key] = theirs
                outcome.apply.insert(key)
                continue
            }
            if wins(theirs, over: mine) {
                outcome.merged[key] = theirs
                outcome.apply.insert(key)
            } else if wins(mine, over: theirs) {
                outcome.push.insert(key)
            }
        }
        outcome.push.formUnion(local.keys.filter { remote[$0] == nil })
        return outcome
    }

    /// The removals old enough to forget.
    static func expiredRemovals(in records: [String: SyncRecord], now: Date) -> Set<String> {
        let limit = now.timeIntervalSince1970 - removalLifetime
        return Set(records.filter { $0.value.isRemoval && $0.value.time < limit }.keys)
    }
}
