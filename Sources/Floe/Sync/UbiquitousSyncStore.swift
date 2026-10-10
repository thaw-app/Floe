//
//  UbiquitousSyncStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// iCloud's key-value store as a `SyncStore`. Made only once the entitlement is known to be there.
final class UbiquitousSyncStore: SyncStore {
    private let store: NSUbiquitousKeyValueStore
    private var observers: [NSObjectProtocol] = []
    var onExternalChange: ((SyncStoreChange) -> Void)?
    let limits = SyncLimits.keyValueStore

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            // Safe: an observer given the main queue is called on the main thread.
            MainActor.assumeIsolated { self?.onExternalChange?(Self.change(reason: reason)) }
        })
        observers.append(center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onExternalChange?(.account) }
        })
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    static nonisolated func change(reason: Int?) -> SyncStoreChange {
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange: .overQuota
        case NSUbiquitousKeyValueStoreAccountChange: .account
        case NSUbiquitousKeyValueStoreInitialSyncChange: .initialValues
        default: .values
        }
    }

    func all() -> [String: Any] {
        store.dictionaryRepresentation
    }

    func set(_ value: [String: Any], for key: String) {
        store.set(value, forKey: key)
    }

    func remove(_ key: String) {
        store.removeObject(forKey: key)
    }

    @discardableResult
    func synchronize() -> Bool {
        store.synchronize()
    }
}
