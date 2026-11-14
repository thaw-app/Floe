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
}
