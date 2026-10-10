//
//  CloudSyncEvents.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Why the server did not take a change.
nonisolated enum CloudSyncFailure: Equatable, Sendable {
    /// The server's record changed since this Mac last saw it. It comes along when the server sent it.
    case conflict(CloudSyncEntry?)
    case zoneMissing
    /// The user deleted the app's data in iCloud's own settings.
    case zonePurged
    /// The record this Mac meant to change is gone from the server.
    case unknownItem
    case quotaExceeded
    /// Another change in the same request failed, and this one was not tried.
    case batch
    /// Worth another try, by the system or at the next exchange.
    case later
    /// The server will not take this change however often it is sent.
    case refused
}

/// How the zone went away.
nonisolated enum CloudSyncZoneLoss: Equatable, Sendable {
    case deleted
    case purged
    /// The user reset their encrypted data; what the Macs hold goes back up.
    case keysReset
}

/// What CloudKit reported, in terms a test can make up.
nonisolated enum CloudSyncEvent: Equatable, Sendable {
    case fetched(changed: [String: CloudSyncEntry], deleted: [String])
    case fetchFinished
    case sent(saved: [String: CloudSyncEntry], deleted: [String], failedSaves: [String: CloudSyncFailure], failedDeletes: [String: CloudSyncFailure])
    case zoneSaved
    case zoneSaveFailed(CloudSyncFailure)
    case zoneDeletionSent
    case zoneDeletionFailed(CloudSyncFailure)
    case zoneLost(CloudSyncZoneLoss)
    case signedIn(String)
    case signedOut
    case switchedAccount(String)
}

/// What to tell the system sync engine after a change or an event.
nonisolated enum CloudSyncCommand: Equatable, Sendable {
    case save(String)
    case delete(String)
    /// Takes a record's queued change back.
    case forget(String)
    /// Takes every queued change back, the zone's among them.
    case forgetEverything
    case saveZone
    case deleteZone
    /// Drops the engine's saved state and starts a new engine, which fetches everything again.
    case restart
    case fetch
}

nonisolated struct CloudSyncEffects: Equatable {
    var commands: [CloudSyncCommand] = []
    var change: SyncStoreChange?

    /// One event reports one change; the one the engine must not miss wins.
    mutating func note(_ new: SyncStoreChange) {
        let order: [SyncStoreChange] = [.values, .initialValues, .account, .overQuota, .removed]
        if (order.firstIndex(of: new) ?? 0) >= (change.flatMap(order.firstIndex) ?? -1) {
            change = new
        }
    }
}
