//
//  AIKeyDraftTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Synchronization
import Testing

@MainActor
struct AIKeyDraftTests {
    private let openAI = "https://api.openai.com/v1"
    private let router = "https://openrouter.ai/api/v1"

    @Test func aDraftReadsTheKeychainOnceAndShowsTheStoredKey() {
        let vault = FakeAIVault()
        vault.keys.save("sk-openai", for: openAI)
        vault.reads.withLock { $0 = 0 }
        let draft = AIKeyDraft(address: openAI, keys: vault.keys)
        #expect(vault.reads.withLock { $0 } == 1)
        #expect(draft.text == "sk-openai")
        #expect(AIKeyDraft(address: router, keys: vault.keys).text == "", "nothing stored shows an empty field")
    }

    @Test func aDraftGivenAKeyReadsNothing() {
        let vault = FakeAIVault()
        let draft = AIKeyDraft(address: openAI, stored: "given", keys: vault.keys)
        #expect(vault.reads.withLock { $0 } == 0)
        #expect(draft.text == "given")
    }

    @Test func savingRightAfterCreationWritesNothing() {
        let vault = FakeAIVault()
        vault.keys.save("sk-openai", for: openAI)
        vault.writes.withLock { $0 = 0 }
        let draft = AIKeyDraft(address: openAI, keys: vault.keys)
        draft.save(for: openAI)
        #expect(vault.writes.withLock { $0 } == 0)
    }

    @Test func aChangedFieldIsWrittenOnceAndNotAgain() {
        let vault = FakeAIVault()
        let draft = AIKeyDraft(address: openAI, keys: vault.keys)
        draft.text = "new"
        draft.save(for: openAI)
        #expect(vault.writes.withLock { $0 } == 1)
        #expect(vault.keys.key(for: openAI) == "new")
        draft.save(for: openAI)
        #expect(vault.writes.withLock { $0 } == 1)
    }

    @Test func anEmptiedFieldRemovesTheStoredKey() {
        let vault = FakeAIVault()
        vault.keys.save("sk-openai", for: openAI)
        let draft = AIKeyDraft(address: openAI, keys: vault.keys)
        draft.text = ""
        draft.save(for: openAI)
        #expect(vault.keys.key(for: openAI) == nil)
        #expect(vault.all.isEmpty)
    }

    @Test func anotherAddressShowsItsOwnKeyWithoutWritingIt() {
        let vault = FakeAIVault()
        vault.keys.save("sk-openai", for: openAI)
        vault.keys.save("sk-router", for: router)
        vault.writes.withLock { $0 = 0 }
        let draft = AIKeyDraft(address: openAI, keys: vault.keys)
        draft.show(address: router)
        #expect(draft.text == "sk-router")
        draft.save(for: router)
        #expect(vault.writes.withLock { $0 } == 0)
    }
}
