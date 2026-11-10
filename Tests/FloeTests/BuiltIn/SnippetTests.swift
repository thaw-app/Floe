//
//  SnippetTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SnippetTests {
    private let sig = Snippet(name: "Signature", keyword: ";sig", text: "Best,\nOwen")
    private let sigLong = Snippet(name: "Long signature", keyword: ";siglong", text: "Best regards")

    @Test func placeholdersAreFilledIn() {
        let uuid = UUID()
        let text = Snippet.expand("{clipboard} {uuid} {missing}", clipboard: "copied", uuid: uuid)
        #expect(text == "copied \(uuid.uuidString) {missing}")
        #expect(!Snippet.expand("{date} {time} {day}", clipboard: "").contains("{"))
    }

    @Test func theLongestKeywordTypedWins() {
        #expect(Snippet.match(typed: "hello ;sig", in: [sig, sigLong])?.name == "Signature")
        #expect(Snippet.match(typed: "x;siglong", in: [sig, sigLong])?.name == "Long signature")
        #expect(Snippet.match(typed: ";si", in: [sig, sigLong]) == nil)
    }

    @Test func keywordsMustBeUsableAndUnique() {
        #expect(Snippet.keywordProblem(";", id: UUID(), among: [sig]) != nil)
        #expect(Snippet.keywordProblem("a b", id: UUID(), among: [sig]) != nil)
        #expect(Snippet.keywordProblem(";sig", id: UUID(), among: [sig]) != nil)
        #expect(Snippet.keywordProblem(";sig", id: sig.id, among: [sig]) == nil, "a snippet keeps its own keyword")
    }

    @Test func keysAreListenedForOnlyWhileASnippetCouldExpand() {
        #expect(Snippet.canExpand([sig], enabled: true))
        #expect(!Snippet.canExpand([sig], enabled: false), "expansion is switched off")
        #expect(!Snippet.canExpand([], enabled: true), "nothing to expand")
        #expect(!Snippet.canExpand([Snippet(name: "No keyword", keyword: "", text: "x")], enabled: true), "a snippet without a keyword is only inserted from the launcher")
    }

    @Test func theFirstLineSkipsBlankLines() {
        #expect(Snippet(name: "n", keyword: "kk", text: "\n  \nHi there\nmore").firstLine == "Hi there")
    }
}
