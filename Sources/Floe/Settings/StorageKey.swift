//
//  StorageKey.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
import Foundation
import Security
import Synchronization

/// The key that seals the clipboard history and that each extension's own LocalStorage key is derived from: 32 random
/// bytes made once on this Mac, kept in the login keychain and never synced. It never leaves the app, and what it
/// seals stays on this Mac too.
nonisolated enum StorageKey {
    static let service = "org.thaw.floe.storage-key"
    static let account = "key-v2"
    /// The key under this account was handed to every extension until this version, so it is replaced. It is kept
    /// only until what it sealed is sealed again, then removed (see StorageMigration).
    static let legacyAccount = "key"

    /// How an extension's key is derived. Fixed forever: changing either makes every extension's storage unreadable.
    static let derivationSalt = Data("org.thaw.floe.storage-key".utf8)
    static let derivationPrefix = "local-storage:"

    /// Set by the app at launch. Tests leave it off, so they never reach the person's keychain.
    nonisolated(unsafe) static var isEnabled = false

    enum Access: Equatable, Sendable {
        /// Storage stays plain: tests, and tools that run without the app.
        case off
        case key(String)
        /// The keychain gave no key just now. Nothing is saved until it does, so nothing sealed is lost.
        case unavailable
    }

    enum Legacy: Equatable, Sendable {
        case none
        case key(String)
        /// The old item is there and could not be read just now: what it sealed must not be written over.
        case unreadable
    }

    private static let found = Mutex<String?>(nil)
    private static let foundLegacy = Mutex<Legacy?>(nil)

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

    /// The old key, kept once it is read. A read that failed is asked again on the next call.
    static func legacyForApp() -> Legacy {
        guard isEnabled else { return .none }
        if let known = foundLegacy.withLock({ $0 }) {
            return known
        }
        let legacy = legacy(in: SystemKeychain())
        if legacy != .unreadable {
            foundLegacy.withLock { $0 = legacy }
        }
        return legacy
    }

    /// Whether the old item is there is asked without reading its secret. A keychain that gives no answer is not one
    /// without the old key: what it sealed stays locked until the keychain answers.
    static func legacy(in keychain: some KeychainAccess) -> Legacy {
        switch keychain.contains(service: service, account: legacyAccount, synchronizable: false) {
        case false?: return .none
        case nil: return .unreadable
        case true?: break
        }
        guard let key = keychain.read(service: service, account: legacyAccount, synchronizable: false) else { return .unreadable }
        // The app never sealed anything with a value that is not 32 bytes, so such a value is no old key.
        return Data(base64Encoded: key)?.count == 32 ? .key(key) : .none
    }

    static func retireLegacy(in keychain: some KeychainAccess = SystemKeychain()) {
        keychain.delete(service: service, account: legacyAccount, synchronizable: false)
    }

    /// The extension's own key, in base64: HKDF-SHA256 of the storage key, bound to the extension's name the way its
    /// data folder is named. Knowing it tells nothing about another extension's key or the storage key.
    static func extensionKey(root: String, name: String) -> String? {
        guard let bytes = Data(base64Encoded: root), bytes.count == 32 else { return nil }
        let info = Data((derivationPrefix + ExtensionCommand.folderKey(name)).utf8)
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), salt: derivationSalt, info: info, outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    /// What an extension's host is given: its own key once its storage has moved off the old key, never the root.
    static func access(forExtension name: String, root: Access, allowed: Bool) -> Access {
        guard case let .key(key) = root else { return root }
        guard allowed, let own = extensionKey(root: key, name: name) else { return .unavailable }
        return .key(own)
    }

    static func symmetricKey(_ base64: String) -> SymmetricKey? {
        Data(base64Encoded: base64).map { SymmetricKey(data: $0) }
    }

    static func forExtension(_ name: String) -> Access {
        access(forExtension: name, root: forApp(), allowed: StorageMigration.shared.allows(name))
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
