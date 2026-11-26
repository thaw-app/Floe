//
//  MemoryKeychain.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Security
import Synchronization

/// A keychain in memory, for tests. It can refuse local or synchronizable writes, and it notes every synchronizable call.
final nonisolated class MemoryKeychain: KeychainAccess {
    private struct Key: Hashable {
        let service: String
        let account: String
        let synchronizable: Bool
    }

    private struct State {
        var items: [Key: (value: String, modified: Date)] = [:]
        var synchronizableCalls = 0
        var failure: OSStatus?
        var localFailure: OSStatus?
        var unreadable: Set<String> = []
        var deleteFailure: OSStatus?
        var time = Date(timeIntervalSince1970: 1000)
    }

    private let state = Mutex(State())

    /// The status every synchronizable write answers with, as a build without the entitlement would. Nil lets them through.
    var synchronizableFailure: OSStatus? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    /// The status every local write answers with, as a locked keychain would. Nil lets them through.
    var localFailure: OSStatus? {
        get { state.withLock { $0.localFailure } }
        set { state.withLock { $0.localFailure = newValue } }
    }

    /// Synchronizable items that are listed but whose value cannot be read, as a keychain that will not hand it over.
    var unreadable: Set<String> {
        get { state.withLock { $0.unreadable } }
        set { state.withLock { $0.unreadable = newValue } }
    }

    /// The status every synchronizable delete answers with, leaving the item. Nil lets them through.
    var deleteFailure: OSStatus? {
        get { state.withLock { $0.deleteFailure } }
        set { state.withLock { $0.deleteFailure = newValue } }
    }

    /// Runs after each local write, outside the lock, as another device changing iCloud Keychain meanwhile would.
    nonisolated(unsafe) var afterLocalWrite: ((_ account: String) -> Void)?

    /// The time the next writes are dated with.
    var time: Date {
        get { state.withLock { $0.time } }
        set { state.withLock { $0.time = newValue } }
    }

    var synchronizableCalls: Int {
        state.withLock { $0.synchronizableCalls }
    }

    private func note(_ synchronizable: Bool, in state: inout State) {
        state.synchronizableCalls += synchronizable ? 1 : 0
    }

    func read(service: String, account: String, synchronizable: Bool) -> String? {
        state.withLock {
            note(synchronizable, in: &$0)
            if synchronizable, $0.unreadable.contains(account) {
                return nil
            }
            return $0.items[Key(service: service, account: account, synchronizable: synchronizable)]?.value
        }
    }

    @discardableResult
    func write(_ value: String, service: String, account: String, synchronizable: Bool) -> OSStatus {
        let status = state.withLock {
            note(synchronizable, in: &$0)
            if let failure = synchronizable ? $0.failure : $0.localFailure {
                return failure
            }
            $0.items[Key(service: service, account: account, synchronizable: synchronizable)] = (value, $0.time)
            return errSecSuccess
        }
        if !synchronizable, status == errSecSuccess {
            afterLocalWrite?(account)
        }
        return status
    }

    @discardableResult
    func add(_ value: String, service: String, account: String) -> OSStatus {
        state.withLock {
            if let failure = $0.localFailure {
                return failure
            }
            let key = Key(service: service, account: account, synchronizable: false)
            guard $0.items[key] == nil else { return errSecDuplicateItem }
            $0.items[key] = (value, $0.time)
            return errSecSuccess
        }
    }

    @discardableResult
    func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
        state.withLock {
            note(synchronizable, in: &$0)
            if synchronizable, let failure = $0.deleteFailure {
                return failure
            }
            return $0.items.removeValue(forKey: Key(service: service, account: account, synchronizable: synchronizable)) == nil ? errSecItemNotFound : errSecSuccess
        }
    }

    func list(service: String, synchronizable: Bool) -> [KeychainEntry] {
        state.withLock {
            note(synchronizable, in: &$0)
            return $0.items.filter { $0.key.service == service && $0.key.synchronizable == synchronizable }
                .map { KeychainEntry(account: $0.key.account, modified: $0.value.modified) }
                .sorted { $0.account < $1.account }
        }
    }

    func contains(service: String, account: String, synchronizable: Bool) -> Bool? {
        state.withLock {
            note(synchronizable, in: &$0)
            return $0.items[Key(service: service, account: account, synchronizable: synchronizable)] != nil
        }
    }
}
