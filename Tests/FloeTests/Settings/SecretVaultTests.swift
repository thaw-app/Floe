//
//  SecretVaultTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Security
import Testing

/// Password sync over a keychain in memory. Nothing here reaches the Mac's Keychain or iCloud.
struct SecretVaultTests {
    private let service = SecretVault.service
    private let keychain = MemoryKeychain()
    private let scratch: ScratchDefaults
    private let vault: SecretVault

    init() throws {
        scratch = try ScratchDefaults()
        vault = SecretVault(keychain: keychain, defaults: scratch.defaults, isEntitled: { true })
    }

    private func local(_ account: String) -> String? {
        keychain.read(service: service, account: account, synchronizable: false)
    }

    private func shared(_ account: String) -> String? {
        keychain.read(service: service, account: account, synchronizable: true)
    }

    @Test func aSecretSavedUnderTheEarlierNameIsMovedWhenItIsRead() {
        let earlier = EarlierIdentifier.secretService
        keychain.write("old", service: earlier, account: "github/token", synchronizable: false)
        #expect(vault.read(account: "github/token") == "old")
        #expect(local("github/token") == "old")
        #expect(keychain.read(service: earlier, account: "github/token", synchronizable: false) == nil)
    }

    @Test func aSecretSavedSinceTheRenameWinsOverAnEarlierOne() {
        let earlier = EarlierIdentifier.secretService
        keychain.write("old", service: earlier, account: "github/token", synchronizable: false)
        vault.write("new", account: "github/token")
        #expect(vault.read(account: "github/token") == "new")
        #expect(keychain.read(service: earlier, account: "github/token", synchronizable: false) == "old")
    }

    @Test func withTheSwitchOffNothingSynchronizableIsWrittenOrRead() {
        keychain.write("elsewhere", service: service, account: "github/token", synchronizable: true)
        let before = keychain.synchronizableCalls
        vault.write("mine", account: "github/token")
        vault.write("key", account: AIEndpoint.keychainAccount)
        #expect(vault.read(account: "github/token") == "mine")
        vault.delete(account: AIEndpoint.keychainAccount)
        #expect(vault.read(account: AIEndpoint.keychainAccount) == nil)
        let status = vault.status
        #expect(!status.isOn)
        #expect(keychain.synchronizableCalls == before)
        #expect(shared("github/token") == "elsewhere")
    }

    @Test func switchingOnMovesTheSecretsAndReadsThemBack() {
        vault.write("gh", account: "github/token")
        vault.write("key", account: AIEndpoint.keychainAccount)
        vault.write("{\"access_token\":\"t\"}", account: "github/oauth/github")
        let isOn = vault.turnOn()
        #expect(isOn)
        #expect(shared("github/token") == "gh")
        #expect(shared(AIEndpoint.keychainAccount) == "key")
        #expect(local("github/token") == nil, "the local copy goes once the new item reads back")
        #expect(local(AIEndpoint.keychainAccount) == nil)
        #expect(vault.read(account: "github/token") == "gh")
        #expect(shared("github/oauth/github") == nil, "a sign-in's tokens never sync")
        #expect(vault.read(account: "github/oauth/github") == "{\"access_token\":\"t\"}")
        #expect(vault.status == SecretSyncStatus(isAvailable: true, isOn: true))
        vault.write("gh2", account: "github/token")
        #expect(shared("github/token") == "gh2")
        #expect(local("github/token") == nil)
        vault.write("{}", account: "github/oauth/github")
        #expect(shared("github/oauth/github") == nil)
    }

    @Test func readsPreferTheSynchronizableItemAndFallBackToTheLocalOne() {
        _ = vault.turnOn()
        keychain.write("local", service: service, account: "a/x", synchronizable: false)
        #expect(vault.read(account: "a/x") == "local")
        keychain.write("shared", service: service, account: "a/x", synchronizable: true)
        #expect(vault.read(account: "a/x") == "shared")
    }

    @Test func aWriteThatFailsKeepsTheLocalItemAndSaysWhy() {
        vault.write("gh", account: "github/token")
        keychain.synchronizableFailure = errSecMissingEntitlement
        let isOn = vault.turnOn()
        #expect(!isOn, "nothing could be stored, so sync stays off")
        #expect(local("github/token") == "gh")
        #expect(vault.read(account: "github/token") == "gh")
        #expect(vault.status == SecretSyncStatus(isAvailable: true, failure: errSecMissingEntitlement))
        #expect(SettingsSyncText.passwordLine(for: vault.status) == "Passwords stay on this Mac. The last change failed: this build of Floe may not use iCloud Keychain.")
    }

    @Test func aWriteThatFailsWhileOnFallsBackToALocalItem() {
        vault.write("gh", account: "github/token")
        _ = vault.turnOn()
        keychain.synchronizableFailure = errSecNotAvailable
        vault.write("new", account: "linear/key")
        #expect(local("linear/key") == "new")
        #expect(shared("linear/key") == nil)
        #expect(vault.read(account: "linear/key") == "new")
        #expect(vault.status == SecretSyncStatus(isAvailable: true, isOn: true, kept: 1, failure: errSecNotAvailable))
        #expect(SettingsSyncText.passwordLine(for: vault.status).hasPrefix("1 of your passwords could not be moved to iCloud Keychain and stay on this Mac. The last change failed: "))
        keychain.synchronizableFailure = nil
        _ = vault.turnOn()
        #expect(shared("linear/key") == "new", "switching on again moves what was left")
        #expect(vault.status == SecretSyncStatus(isAvailable: true, isOn: true))
    }

    @Test func aBuildWithoutTheEntitlementIsNeverSwitchedOn() {
        let unsigned = SecretVault(keychain: keychain, defaults: scratch.defaults, isEntitled: { false })
        unsigned.write("gh", account: "github/token")
        let isOn = unsigned.turnOn()
        let removed = unsigned.removeEverywhere()
        #expect(!isOn)
        #expect(!removed)
        #expect(!unsigned.isOn)
        #expect(keychain.synchronizableCalls == 0)
        #expect(SettingsSyncText.passwordLine(for: unsigned.status) == "Unavailable: this build of Floe is not signed for iCloud Keychain.")
    }

    @Test func switchingOffCopiesBackAndLeavesTheSynchronizableItems() {
        vault.write("gh", account: "github/token")
        _ = vault.turnOn()
        keychain.write("from the other Mac", service: service, account: "linear/key", synchronizable: true)
        let isOff = vault.turnOff()
        #expect(isOff)
        #expect(!vault.isOn)
        #expect(local("github/token") == "gh")
        #expect(local("linear/key") == "from the other Mac")
        #expect(shared("github/token") == "gh", "deleting it here would delete it on every device")
        #expect(shared("linear/key") == "from the other Mac")
        let before = keychain.synchronizableCalls
        vault.write("changed here", account: "github/token")
        #expect(vault.read(account: "github/token") == "changed here")
        #expect(keychain.synchronizableCalls == before, "once off, the synchronizable items are not read or written")
    }

    @Test func removingEverywhereDeletesTheSynchronizableItemsAndKeepsThisMacs() {
        vault.write("gh", account: "github/token")
        vault.write("key", account: AIEndpoint.keychainAccount)
        _ = vault.turnOn()
        let removed = vault.removeEverywhere()
        #expect(removed)
        #expect(!vault.isOn)
        #expect(keychain.list(service: service, synchronizable: true).isEmpty)
        #expect(vault.read(account: "github/token") == "gh")
        #expect(vault.read(account: AIEndpoint.keychainAccount) == "key")
    }

    @Test func joiningKeepsTheNewerOfTwoDifferentSecrets() {
        keychain.time = Date(timeIntervalSince1970: 2000)
        keychain.write("older here", service: service, account: "a/x", synchronizable: false)
        keychain.write("newer elsewhere", service: service, account: "b/y", synchronizable: true)
        keychain.time = Date(timeIntervalSince1970: 3000)
        keychain.write("newer elsewhere", service: service, account: "a/x", synchronizable: true)
        keychain.write("newer here", service: service, account: "b/y", synchronizable: false)
        _ = vault.turnOn()
        #expect(vault.read(account: "a/x") == "newer elsewhere")
        #expect(vault.read(account: "b/y") == "newer here")
        #expect(shared("b/y") == "newer here")
        #expect(keychain.list(service: service, synchronizable: false).isEmpty)
    }

    @Test func clearingASecretWhileOnRemovesItEverywhere() {
        vault.write("gh", account: "github/token")
        _ = vault.turnOn()
        vault.delete(account: "github/token")
        #expect(shared("github/token") == nil)
        #expect(vault.read(account: "github/token") == nil)
    }

    @Test func onlyOAuthTokensAreHeldBack() {
        #expect(SecretVault.syncs("github/token"))
        #expect(SecretVault.syncs("github/search/token"))
        #expect(SecretVault.syncs(AIEndpoint.keychainAccount))
        #expect(!SecretVault.syncs("github/oauth/github"))
    }

    @Test func thePrivacyRowSaysWherePasswordsAre() {
        #expect(SettingsSyncText.privacyLine(isOn: true, includesExtensions: true, passwords: true).contains("kept in iCloud Keychain"))
        #expect(!SettingsSyncText.privacyLine(isOn: true, includesExtensions: true, passwords: true).contains("Passwords, keys"))
        #expect(SettingsSyncText.passwordLine(for: SecretSyncStatus(isAvailable: true, isOn: true)) == "Passwords are kept in iCloud Keychain.")
        #expect(SettingsSyncText.passwordLine(for: SecretSyncStatus(isAvailable: true)) == "Passwords stay on this Mac.")
    }
}
