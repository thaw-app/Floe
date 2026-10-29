//
//  AIKeysTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// Accounts and their secrets, in memory, in place of the Keychain.
final nonisolated class FakeAIVault: Sendable {
    let accounts: Mutex<[String: String]>

    init(_ accounts: [String: String] = [:]) {
        self.accounts = Mutex(accounts)
    }

    var all: [String: String] {
        accounts.withLock { $0 }
    }

    var keys: AIKeys {
        AIKeys(
            read: { account in self.accounts.withLock { $0[account] } },
            write: { key, account in self.accounts.withLock { $0[account] = key } },
            delete: { account in _ = self.accounts.withLock { $0.removeValue(forKey: account) } }
        )
    }
}

struct AIKeysTests {
    private let openAI = AIKeys.account(for: "https://api.openai.com")

    @Test func aKeyIsBoundToTheSchemeHostAndPortOfItsAddress() {
        #expect(AIKeys.origin(of: URL(string: "https://API.OpenAI.com/v1/chat/completions")) == "https://api.openai.com")
        #expect(AIKeys.origin(of: URL(string: "https://api.openai.com:443/v1")) == "https://api.openai.com")
        #expect(AIKeys.origin(of: URL(string: "https://gateway.test:8443/v1")) == "https://gateway.test:8443")
        #expect(AIKeys.origin(of: URL(string: "http://localhost:11434/v1")) == nil, "a server on this Mac takes no key")
        #expect(AIKeys.origin(of: nil) == nil)
    }

    @Test func aKeySavedForOneServiceIsNotReadForAnother() {
        let vault = FakeAIVault()
        vault.keys.save("sk-openai", for: "https://api.openai.com/v1")
        #expect(vault.keys.key(for: "https://api.openai.com/v1") == "sk-openai")
        #expect(vault.keys.key(for: "") == "sk-openai", "an empty address is OpenAI's")
        #expect(vault.keys.key(for: "https://openrouter.ai/api/v1") == nil)
        #expect(vault.keys.key(for: "https://attacker.test/v1") == nil)
        #expect(vault.keys.key(for: "http://localhost:11434/v1") == nil)
        vault.keys.save("sk-router", for: "https://openrouter.ai/api/v1")
        #expect(vault.keys.key(for: "https://openrouter.ai/api/v1") == "sk-router")
        #expect(vault.keys.key(for: "https://api.openai.com/v1") == "sk-openai", "switching back finds the first key again")
    }

    @Test func emptyingTheFieldRemovesOnlyThatAddresssKey() {
        let vault = FakeAIVault()
        vault.keys.save("sk-openai", for: "https://api.openai.com/v1")
        vault.keys.save("sk-router", for: "https://openrouter.ai/api/v1")
        vault.keys.save("", for: "https://openrouter.ai/api/v1")
        #expect(vault.all == [openAI: "sk-openai"])
        vault.keys.save("typed", for: "http://localhost:11434/v1")
        #expect(vault.all == [openAI: "sk-openai"], "a server on this Mac keeps no key")
    }

    @Test func aKeySavedBeforeKeysWereBoundIsNeverTakenByAnAddressThatIsRead() {
        let vault = FakeAIVault([AIEndpoint.keychainAccount: "sk-earlier"])
        #expect(vault.keys.key(for: "http://localhost:11434/v1") == nil, "a server on this Mac does not take it")
        #expect(vault.keys.key(for: "https://openrouter.ai/api/v1") == nil, "a service picked later does not take it")
        #expect(vault.keys.key(for: "https://e") == nil, "nor does an address half typed")
        #expect(vault.all == [AIEndpoint.keychainAccount: "sk-earlier"])
    }

    @Test func atLaunchTheEarlierKeyIsBoundToTheAddressInUse() {
        let vault = FakeAIVault([AIEndpoint.keychainAccount: "sk-earlier"])
        vault.keys.bindEarlierKey(inUseWith: "https://api.openai.com/v1")
        #expect(vault.keys.key(for: "https://api.openai.com/v1") == "sk-earlier")
        #expect(vault.all == [openAI: "sk-earlier"])
        #expect(vault.keys.key(for: "https://attacker.test/v1") == nil)
    }

    @Test func beforeAnImportTheEarlierKeyIsBoundToTheAddressInUse() {
        let vault = FakeAIVault([AIEndpoint.keychainAccount: "sk-earlier"])
        vault.keys.bindEarlierKey(inUseWith: "https://api.openai.com/v1")
        #expect(vault.all == [openAI: "sk-earlier"])
        #expect(vault.keys.key(for: "https://attacker.test/v1") == nil)
    }

    @Test(arguments: ["http://localhost:11434/v1", "https://api.openai.com/v1"])
    func beforeAnImportAnEarlierKeyNoAddressInUseTakesIsRemoved(address: String) {
        // The second address already has a key of its own, so the earlier one belongs to no address in use.
        let vault = FakeAIVault([AIEndpoint.keychainAccount: "sk-earlier", openAI: "sk-openai"])
        vault.keys.bindEarlierKey(inUseWith: address)
        #expect(vault.all == [openAI: "sk-openai"])
        #expect(vault.keys.key(for: "https://attacker.test/v1") == nil)
    }

    @Test func anImportedAddressIsSentNoKeySavedForAnother() throws {
        let vault = FakeAIVault()
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        here.aiSource = .api
        here.aiModel = "gpt"
        vault.keys.save("sk-openai", for: here.aiBaseURL)
        let configured = { AIAnswer.choice(source: here.aiSource, baseURL: here.aiBaseURL, model: here.aiModel) { vault.keys.key(for: here.aiBaseURL) } }
        #expect(configured() == .api(AIEndpoint(baseURL: AIEndpoint.defaultBaseURL, model: "gpt", apiKey: "sk-openai")))

        let file = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        file.aiSource = .api
        file.aiModel = "gpt"
        file.aiBaseURL = "https://attacker.test/v1"
        vault.keys.bindEarlierKey(inUseWith: here.aiBaseURL)
        try here.importJSON(file.exportedJSON())

        #expect(here.aiBaseURL == "https://attacker.test/v1")
        #expect(configured() == .api(nil), "the address needs a key of its own before anything is sent")
    }
}
