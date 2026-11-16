//
//  StorageKeyTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Security
import Testing

struct StorageKeyTests {
    @Test func theFirstUseMakesA32ByteKeyAndEveryLaterUseGetsTheSameOne() throws {
        let keychain = MemoryKeychain()
        let first = try #require(StorageKey.current(in: keychain))
        #expect(Data(base64Encoded: first)?.count == 32)
        #expect(StorageKey.current(in: keychain) == first)
    }

    /// A keychain that holds the key but could not read it just now, as a locked one may.
    private final class Unreadable: KeychainAccess, @unchecked Sendable {
        var stored = "the real key"
        /// Whether the old item is there. Nil is no answer.
        var present: Bool? = false
        func read(service _: String, account _: String, synchronizable _: Bool) -> String? {
            nil
        }

        func write(_ value: String, service _: String, account _: String, synchronizable _: Bool) -> OSStatus {
            stored = value
            return errSecSuccess
        }

        func add(_: String, service _: String, account _: String) -> OSStatus {
            errSecDuplicateItem
        }

        func delete(service _: String, account _: String, synchronizable _: Bool) -> OSStatus {
            errSecSuccess
        }

        func list(service _: String, synchronizable _: Bool) -> [KeychainEntry] {
            []
        }

        func contains(service _: String, account _: String, synchronizable _: Bool) -> Bool? {
            present
        }
    }

    @Test func aKeyThatCouldNotBeReadIsNeverReplacedAndLocksTheStorage() {
        let keychain = Unreadable()
        #expect(StorageKey.current(in: keychain) == nil)
        #expect(keychain.stored == "the real key", "a new key would leave every extension's storage unreadable")
        #expect(StorageKey.access(enabled: true, in: keychain) == .unavailable)
        #expect(StorageKey.access(enabled: false, in: keychain) == .off, "tests and tools without the app keep plain storage")
    }

    @Test func aKeyThatIsNot32BytesLocksTheStorageAndNeverLeavesItPlain() {
        let keychain = MemoryKeychain()
        keychain.write("not a key", service: StorageKey.service, account: StorageKey.account, synchronizable: false)
        #expect(StorageKey.access(enabled: true, in: keychain) == .unavailable)
    }

    @Test func passwordsAndTheKeyGoOnTheHostsInputAndNotInItsEnvironment() throws {
        let line = ExtensionSession.secretsLine(preferences: Data(#"{"token":"secret"}"#.utf8), storage: .key("a2V5"))
        #expect(line.last == 0x0A)
        let message = try #require(JSONSerialization.jsonObject(with: Data(line.dropLast())) as? [String: Any])
        #expect(message["type"] as? String == "secrets")
        #expect(message["preferences"] as? String == #"{"token":"secret"}"#)
        #expect(message["storageKey"] as? String == "a2V5")
        #expect(message["storageLocked"] as? Bool == false)
        let locked = try #require(JSONSerialization.jsonObject(with: Data(ExtensionSession.secretsLine(preferences: nil, storage: .unavailable).dropLast())) as? [String: Any])
        #expect(locked["storageLocked"] as? Bool == true)
        #expect(locked["storageKey"] == nil)

        let variables = ExtensionSession.hostVariables(["FLOE_PREFERENCES": "stale"], grants: [])
        #expect(variables["FLOE_SECRETS"] == "input")
        #expect(variables["FLOE_PREFERENCES"] == nil)
        #expect(variables["FLOE_STORAGE_KEY"] == nil)
    }

    // MARK: Each extension's own key

    private let ones = Data(repeating: 1, count: 32).base64EncodedString()

    @Test func anExtensionsKeyIsTheOneTheRuntimeWouldDerive() {
        // Made with node:crypto's hkdfSync, outside this code. Fixed forever: if this changes, every extension's
        // storage becomes unreadable.
        #expect(StorageKey.extensionKey(root: ones, name: "github") == "TN/bpI0dIMYpRybu2md5292MXGfh0iV5gqRpnH3oKtg=")
        #expect(StorageKey.extensionKey(root: ones, name: "GitHub") == "TN/bpI0dIMYpRybu2md5292MXGfh0iV5gqRpnH3oKtg=", "one data folder, one key")
        #expect(StorageKey.extensionKey(root: "not a key", name: "github") == nil)
    }

    @Test func twoExtensionsGetDifferentKeysAndNeitherIsTheRoot() {
        let github = StorageKey.extensionKey(root: ones, name: "github")
        let notes = StorageKey.extensionKey(root: ones, name: "notes")
        #expect(github != notes)
        #expect(github != ones)
        #expect(notes != ones)
    }

    @Test func theNewKeyIsMadeBesideTheOldOneAndLeavesItAlone() throws {
        let keychain = MemoryKeychain()
        keychain.write(ones, service: StorageKey.service, account: StorageKey.legacyAccount, synchronizable: false)
        let made = try #require(StorageKey.current(in: keychain))
        #expect(made != ones)
        #expect(keychain.read(service: StorageKey.service, account: StorageKey.account, synchronizable: false) == made)
        #expect(keychain.read(service: StorageKey.service, account: StorageKey.legacyAccount, synchronizable: false) == ones)
    }

    @Test func theOldKeyIsFoundOnlyWhenItIsThereAndIsAKey() {
        let keychain = MemoryKeychain()
        #expect(StorageKey.legacy(in: keychain) == .none)
        keychain.write(ones, service: StorageKey.service, account: StorageKey.legacyAccount, synchronizable: false)
        #expect(StorageKey.legacy(in: keychain) == .key(ones))
        keychain.write("not a key", service: StorageKey.service, account: StorageKey.legacyAccount, synchronizable: false)
        #expect(StorageKey.legacy(in: keychain) == .none, "nothing was ever sealed with it")
        StorageKey.retireLegacy(in: keychain)
        #expect(keychain.list(service: StorageKey.service, synchronizable: false).isEmpty)

        let unreadable = Unreadable()
        #expect(StorageKey.legacy(in: unreadable) == .none)
        unreadable.present = true
        #expect(StorageKey.legacy(in: unreadable) == .unreadable)
        unreadable.present = nil
        #expect(StorageKey.legacy(in: unreadable) == .unreadable, "a keychain that gave no answer may still hold the old key")
    }

    @Test func aHostIsGivenItsOwnKeyOnlyWhenAllowedAndNeverTheRoot() {
        #expect(StorageKey.access(forExtension: "github", root: .off, allowed: true) == .off)
        #expect(StorageKey.access(forExtension: "github", root: .unavailable, allowed: true) == .unavailable)
        #expect(StorageKey.access(forExtension: "github", root: .key(ones), allowed: false) == .unavailable)
        let own = StorageKey.access(forExtension: "github", root: .key(ones), allowed: true)
        #expect(own == StorageKey.extensionKey(root: ones, name: "github").map(StorageKey.Access.key))
        #expect(own != .key(ones))
    }
}
