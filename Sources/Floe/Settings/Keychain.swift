//
//  Keychain.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Security
import Synchronization

nonisolated struct KeychainEntry: Equatable, Sendable {
    let account: String
    /// When the item last changed, where the keychain says.
    let modified: Date?
}

/// Every Keychain call Floe makes. A synchronizable item is one iCloud Keychain carries to the person's other devices;
/// writing or deleting one does so on all of them.
nonisolated protocol KeychainAccess: Sendable {
    func read(service: String, account: String, synchronizable: Bool) -> String?
    @discardableResult
    func write(_ value: String, service: String, account: String, synchronizable: Bool) -> OSStatus
    @discardableResult
    func delete(service: String, account: String, synchronizable: Bool) -> OSStatus
    func list(service: String, synchronizable: Bool) -> [KeychainEntry]
}

/// The Mac's keychains: the login keychain for local items, the data protection keychain for synchronizable ones.
nonisolated struct SystemKeychain: KeychainAccess {
    private func query(_ service: String, _ account: String?, _ synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        query[kSecAttrAccount as String] = account
        if synchronizable {
            query[kSecAttrSynchronizable as String] = true
            // On macOS a synchronizable item lives only in the data protection keychain.
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    func read(service: String, account: String, synchronizable: Bool) -> String? {
        var query = query(service, account, synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ value: String, service: String, account: String, synchronizable: Bool) -> OSStatus {
        let data = Data(value.utf8)
        let updated = SecItemUpdate(query(service, account, synchronizable) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updated == errSecItemNotFound else { return updated }
        var item = query(service, account, synchronizable)
        item[kSecValueData as String] = data
        // A local secret (OAuth tokens among them) stays on this device; one that syncs cannot be device-only.
        item[kSecAttrAccessible as String] = synchronizable ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil)
    }

    @discardableResult
    func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
        SecItemDelete(query(service, account, synchronizable) as CFDictionary)
    }

    func list(service: String, synchronizable: Bool) -> [KeychainEntry] {
        var query = query(service, nil, synchronizable)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            (item[kSecAttrAccount as String] as? String).map { KeychainEntry(account: $0, modified: item[kSecAttrModificationDate as String] as? Date) }
        }
    }
}

/// A keychain in memory, for tests. It can refuse synchronizable writes, and it notes every synchronizable call.
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
        var time = Date(timeIntervalSince1970: 1000)
    }

    private let state = Mutex(State())

    /// The status every synchronizable write answers with, as a build without the entitlement would. Nil lets them through.
    var synchronizableFailure: OSStatus? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

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
            return $0.items[Key(service: service, account: account, synchronizable: synchronizable)]?.value
        }
    }

    @discardableResult
    func write(_ value: String, service: String, account: String, synchronizable: Bool) -> OSStatus {
        state.withLock {
            note(synchronizable, in: &$0)
            if synchronizable, let failure = $0.failure {
                return failure
            }
            $0.items[Key(service: service, account: account, synchronizable: synchronizable)] = (value, $0.time)
            return errSecSuccess
        }
    }

    @discardableResult
    func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
        state.withLock {
            note(synchronizable, in: &$0)
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
}

/// How password sync is doing, for Settings to show.
nonisolated struct SecretSyncStatus: Equatable, Sendable {
    var isAvailable = false
    var isOn = false
    /// Secrets that should be in iCloud Keychain and are still only on this Mac.
    var kept = 0
    /// Why the last change did not go through, as the keychain's status code.
    var failure: OSStatus?
}

/// Floe's secrets: extension passwords, the AI key and OAuth tokens. With password sync on, the first two are
/// synchronizable items; tokens never are, because a token refreshed on one Mac would end the other's.
final nonisolated class SecretVault: Sendable {
    static let service = "org.thaw.floe.preferences"
    /// Kept apart from `AppSettings`, so an import or a sync cannot switch it without the copy that goes with it.
    static let onKey = "syncsPasswordsWithKeychain"
    static let failureKey = "passwordSyncFailure"

    static let system = SecretVault(keychain: SystemKeychain(), defaults: .standard, isEntitled: hasKeychainEntitlement)

    private let keychain: any KeychainAccess
    /// Safe: `UserDefaults` is documented as thread-safe, and this never replaces it.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let isEntitled: @Sendable () -> Bool

    init(keychain: any KeychainAccess, defaults: UserDefaults, isEntitled: @escaping @Sendable () -> Bool) {
        self.keychain = keychain
        self.defaults = defaults
        self.isEntitled = isEntitled
    }

    /// The data protection keychain answers only a process signed with an application identifier or an access group.
    /// Asked of the running process, so a build without one is never offered the switch.
    static func hasKeychainEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let identifier = SecTaskCopyValueForEntitlement(task, "com.apple.application-identifier" as CFString, nil) as? String
        let groups = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) as? [String]
        return identifier?.isEmpty == false || groups?.isEmpty == false
    }

    /// Whether an account's secret may sync. An OAuth token is "<extension>/oauth/<provider>" and never does.
    static func syncs(_ account: String) -> Bool {
        let parts = account.split(separator: "/", omittingEmptySubsequences: false)
        return !(parts.count >= 3 && parts[1] == "oauth")
    }

    var isAvailable: Bool {
        isEntitled()
    }

    var isOn: Bool {
        defaults.bool(forKey: Self.onKey)
    }

    var status: SecretSyncStatus {
        let failure = (defaults.object(forKey: Self.failureKey) as? Int).map(OSStatus.init)
        guard isOn else { return SecretSyncStatus(isAvailable: isAvailable, failure: failure) }
        return SecretSyncStatus(isAvailable: isAvailable, isOn: true, kept: local().count, failure: failure)
    }

    func read(account: String) -> String? {
        if isOn, Self.syncs(account), let value = keychain.read(service: Self.service, account: account, synchronizable: true) {
            return value
        }
        return keychain.read(service: Self.service, account: account, synchronizable: false) ?? takeEarlier(account)
    }

    /// A secret saved before Floe was renamed, moved to where it is looked for now. macOS asks before handing it over.
    private func takeEarlier(_ account: String) -> String? {
        let service = EarlierIdentifier.secretService
        guard let value = keychain.read(service: service, account: account, synchronizable: false) else { return nil }
        write(value, account: account)
        keychain.delete(service: service, account: account, synchronizable: false)
        return value
    }

    func write(_ value: String, account: String) {
        guard isOn, Self.syncs(account) else {
            keychain.write(value, service: Self.service, account: account, synchronizable: false)
            return
        }
        let status = move(value, account: account)
        if status != errSecSuccess {
            // The secret is never lost to a keychain that refused it: it stays a local item.
            keychain.write(value, service: Self.service, account: account, synchronizable: false)
            defaults.set(Int(status), forKey: Self.failureKey)
        }
    }

    /// With sync on this removes the secret on every device, which is what clearing a synced password means.
    func delete(account: String) {
        keychain.delete(service: Self.service, account: account, synchronizable: false)
        if isOn, Self.syncs(account) {
            keychain.delete(service: Self.service, account: account, synchronizable: true)
        }
    }

    /// Copies this Mac's secrets to synchronizable items. Where iCloud Keychain already holds a different one,
    /// the newer of the two is kept. False when nothing could be stored, and sync is then left off.
    @discardableResult
    func turnOn() -> Bool {
        guard isAvailable else { return false }
        // On before the copy, so a secret is found wherever it is while the copy runs.
        defaults.set(true, forKey: Self.onKey)
        let synced = Dictionary(shared().map { ($0.account, $0.modified) }) { first, _ in first }
        var failure = errSecSuccess
        var moved = 0
        for entry in local() {
            guard let mine = keychain.read(service: Self.service, account: entry.account, synchronizable: false) else { continue }
            let theirs = keychain.read(service: Self.service, account: entry.account, synchronizable: true)
            let mineIsNewer = (synced[entry.account] ?? nil).flatMap { changed in entry.modified.map { $0 > changed } } ?? false
            if let theirs, theirs == mine || !mineIsNewer {
                keychain.delete(service: Self.service, account: entry.account, synchronizable: false)
                continue
            }
            let status = move(mine, account: entry.account)
            failure = status == errSecSuccess ? failure : status
            moved += status == errSecSuccess ? 1 : 0
        }
        guard failure != errSecSuccess else {
            defaults.removeObject(forKey: Self.failureKey)
            return true
        }
        defaults.set(Int(failure), forKey: Self.failureKey)
        if moved == 0, synced.isEmpty {
            defaults.set(false, forKey: Self.onKey)
            return false
        }
        return true
    }

    /// Copies the synchronizable secrets back to local items and stops reading synchronizable ones. They are not
    /// deleted: deleting one deletes it on every device. False, and still on, when a copy could not be made.
    @discardableResult
    func turnOff() -> Bool {
        guard isOn else { return true }
        let failure = copyBack()
        guard failure == errSecSuccess else {
            defaults.set(Int(failure), forKey: Self.failureKey)
            return false
        }
        defaults.set(false, forKey: Self.onKey)
        defaults.removeObject(forKey: Self.failureKey)
        return true
    }

    /// Deletes Floe's synchronizable secrets on every device, after this Mac has its own copies.
    /// Works with sync off too, for a Mac that left them behind.
    @discardableResult
    func removeEverywhere() -> Bool {
        guard isAvailable else { return false }
        let failure = copyBack()
        guard failure == errSecSuccess else {
            defaults.set(Int(failure), forKey: Self.failureKey)
            return false
        }
        defaults.set(false, forKey: Self.onKey)
        defaults.removeObject(forKey: Self.failureKey)
        for entry in shared() {
            keychain.delete(service: Self.service, account: entry.account, synchronizable: true)
        }
        return true
    }

    private func local() -> [KeychainEntry] {
        keychain.list(service: Self.service, synchronizable: false).filter { Self.syncs($0.account) }
    }

    private func shared() -> [KeychainEntry] {
        keychain.list(service: Self.service, synchronizable: true).filter { Self.syncs($0.account) }
    }

    /// Writes a synchronizable item and removes the local one only once the new item reads back.
    private func move(_ value: String, account: String) -> OSStatus {
        let status = keychain.write(value, service: Self.service, account: account, synchronizable: true)
        guard status == errSecSuccess else { return status }
        guard keychain.read(service: Self.service, account: account, synchronizable: true) == value else { return errSecItemNotFound }
        keychain.delete(service: Self.service, account: account, synchronizable: false)
        return errSecSuccess
    }

    private func copyBack() -> OSStatus {
        var failure = errSecSuccess
        for entry in shared() {
            guard let value = keychain.read(service: Self.service, account: entry.account, synchronizable: true) else { continue }
            let status = keychain.write(value, service: Self.service, account: entry.account, synchronizable: false)
            if status != errSecSuccess {
                failure = status
            } else if keychain.read(service: Self.service, account: entry.account, synchronizable: false) != value {
                failure = errSecItemNotFound
            }
        }
        return failure
    }
}

/// Where the rest of Floe reads and writes a secret, by account.
nonisolated enum Keychain {
    static let vault = SecretVault.system

    static func read(account: String) -> String? {
        vault.read(account: account)
    }

    static func write(_ value: String, account: String) {
        vault.write(value, account: account)
    }

    static func delete(account: String) {
        vault.delete(account: account)
    }
}
