//
//  ExtensionCreationsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// What Action.CreateSnippet and Action.CreateQuicklink keep, in stores of the test's own.
@MainActor
struct ExtensionCreationsTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-creations-\(UUID().uuidString)")

    private func refusal(_ body: () throws -> Void) -> String? {
        do {
            try body()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test func aSnippetIsKeptTrimmedAndOneWithoutAKeywordOrATakenOneIsRefused() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SnippetStore(file: folder.appendingPathComponent("snippets.json"))

        try ExtensionCreations.snippet(["name": " Greeting ", "text": "Hello {clipboard}", "keyword": "hi "], in: store)
        #expect(store.snippets.map { [$0.name, $0.keyword, $0.text] } == [["Greeting", "hi", "Hello {clipboard}"]])

        #expect(refusal { try ExtensionCreations.snippet(["name": "Other", "text": "Hey", "keyword": "hi"], in: store) } != nil)
        #expect(refusal { try ExtensionCreations.snippet(["name": "Other", "text": "Hey"], in: store) } != nil)
        #expect(refusal { try ExtensionCreations.snippet(["name": "", "text": "Hey", "keyword": "hey"], in: store) } != nil)
        #expect(store.snippets.count == 1)
    }

    @Test func aQuicklinkIsKeptWithRaycastsArgumentAsTheQueryAndARefusalSaysWhy() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = QuicklinkStore(file: folder.appendingPathComponent("quicklinks.json"))
        let before = store.links.count

        try ExtensionCreations.quicklink(["name": "Docs", "link": "https://docs.example.com/?q={argument name=\"Term\"}", "keyword": "docs"], in: store)
        #expect(store.links.count == before + 1)
        #expect(store.links.last?.url == "https://docs.example.com/?q={query}")

        #expect(refusal { try ExtensionCreations.quicklink(["name": "Docs", "link": "https://example.com", "keyword": "docs"], in: store) } == "That keyword is already used.")
        #expect(refusal { try ExtensionCreations.quicklink(["name": "Page", "link": "example.com", "keyword": "page"], in: store) } != nil)
        #expect(store.links.count == before + 1)
    }
}
