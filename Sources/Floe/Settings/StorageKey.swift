//
//  StorageKey.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Security
import Synchronization

/// The key that seals the clipboard history and extensions' LocalStorage: 32 random bytes made once on this Mac,
/// kept in the login keychain and never synced. What it seals stays on this Mac too.
nonisolated enum StorageKey {
    static let service = "org.thaw.floe.storage-key"
    static let account = "key"

    /// Set by the app at launch. Tests leave it off, so they never reach the person's keychain.
    nonisolated(unsafe) static var isEnabled = false

    enum Access: Equatable, Sendable {
        /// Storage stays plain: tests, and tools that run without the app.
        case off
        case key(String)
        /// The keychain gave no key just now. Nothing is saved until it does, so nothing sealed is lost.
        case unavailable
    }

    private static let found = Mutex<String?>(nil)

    /// The app's key, kept once it is read and read again after a miss.
    static func forApp() -> Access {
        if let key = found.withLock({ $0 }) {
            return .key(key)
        }
        let access = access(enabled: isEnabled, in: SystemKeychain())
        if case let .key(key) = access {
            found.withLock { $0 = key }
        }
        return access
    }

    static func access(enabled: Bool, in keychain: some KeychainAccess) -> Access {
        guard enabled else { return .off }
        // Anything but 32 bytes is no key, and a key that is not there is never taken for no encryption.
        guard let key = current(in: keychain), Data(base64Encoded: key)?.count == 32 else { return .unavailable }
        return .key(key)
    }

    /// The key in base64, made on first use. Nil when the keychain gives none: the storage then stays plain, and
    /// a key that is there but could not be read is never replaced, since that would lose what it sealed.
    static func current(in keychain: some KeychainAccess = SystemKeychain()) -> String? {
        if let key = keychain.read(service: service, account: account, synchronizable: false) {
            return key
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let key = Data(bytes).base64EncodedString()
        switch keychain.add(key, service: service, account: account) {
        case errSecSuccess: return key
        // Another process made it first.
        case errSecDuplicateItem: return keychain.read(service: service, account: account, synchronizable: false)
        default: return nil
        }
    }
}
