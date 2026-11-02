//
//  FoundRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// Keywords, definitions, answers, bookmarks and the calculator as a row owner, on a pasteboard of their own.
@MainActor
final class FoundRowsTests {
    private let board = NSPasteboard.withUniqueName()
    private let asked = CallLog()
    private let rows = FoundRows()

    init() {
        let asked = asked
        rows.pasteboard = board
        rows.host = RowHost(
            showHUD: { asked.note("hud: \($0)") },
            leave: { asked.note("leave") },
            reach: { asked.note("reach: \($0?.absoluteString ?? "nil")") }
        )
        rows.typeQuery = { asked.note("type: \($0)") }
    }

    isolated deinit {
        board.releaseGlobally()
    }

    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @Test func returnOnAnAnswerCopiesItAndAPasswordIsMarkedConcealed() {
        #expect(rows.open(.answer(AnswerRow(id: "uuid", text: "1234", kind: "UUID", symbol: "number")), flags: []))
        #expect(board.string(forType: .string) == "1234")
        #expect(board.string(forType: Self.concealed) == nil)

        #expect(rows.open(.answer(AnswerRow(id: "password", text: "s3cret", kind: "Password", symbol: "key", isSecret: true)), flags: []))
        #expect(board.string(forType: .string) == "s3cret")
        #expect(board.string(forType: Self.concealed) == "")
        #expect(asked.all == ["hud: Copied Answer", "leave", "hud: Copied Answer", "leave"])
        #expect(rows.returnTitle(for: .answer(AnswerRow(id: "uuid", text: "1234", kind: "UUID", symbol: "number"))) == "Copy to Clipboard")
    }

    @Test func returnOnAnAnswerWithALinkReachesItAndCopiesNothing() {
        var answer = AnswerRow(id: "translate", text: "Spanish to German is not downloaded", kind: "Translation", symbol: "globe")
        answer.link = URL(string: "x-apple.systempreferences:com.apple.Localization")
        #expect(rows.returnTitle(for: .answer(answer)) == "Open")
        #expect(rows.open(.answer(answer), flags: []))
        #expect(asked.all == ["reach: x-apple.systempreferences:com.apple.Localization"])
        #expect(board.string(forType: .string) == nil)
    }

    @Test func returnOnADefinitionShowsTheWholeEntryInFloe() {
        let definition = WordDefinition(word: "floe", entry: "floe\nnoun\n a sheet of floating ice\n")
        var shown: [String] = []
        rows.showOutput = { shown.append("\($0)|\($1)") }
        #expect(rows.open(.definition(definition), flags: []))
        #expect(shown == ["floe|floe\nnoun\n a sheet of floating ice"], "with its line breaks")
        #expect(rows.returnTitle(for: .definition(definition)) == "Show Definition")
    }

    @Test func returnOnAKeywordTypesItAndOnABookmarkReachesIt() throws {
        let hint = KeywordHint(keyword: "define", example: "define floe", detail: "Look up a word")
        let bookmark = WebBookmark(title: "Floe", url: try #require(URL(string: "https://example.com")), browser: "Safari")
        #expect(rows.open(.keyword(hint), flags: []))
        #expect(rows.open(.bookmark(bookmark), flags: []))
        #expect(asked.all == ["type: define ", "reach: https://example.com"])
        #expect(rows.returnTitle(for: .keyword(hint)) == "Type Keyword")
    }

    @Test func aDefinitionsMenuOpensTheDictionaryAppOrCopiesWhatItSays() throws {
        let definition = WordDefinition(word: "floe", entry: "floe a sheet of floating ice")
        let actions = try #require(rows.actions(for: .definition(definition)))
        #expect(actions.compactMap { $0?.title } == ["Open in Dictionary", "Copy Definition"])
        actions.first??.run()
        actions.last??.run()
        #expect(board.string(forType: .string) == "floe a sheet of floating ice")
        #expect(asked.all == ["reach: dict://floe", "hud: Copied floe", "leave"])
    }

    @Test func returnOnTheCalculatorCopiesTheAnswerOrSaysWhyNot() {
        #expect(rows.open(.calculator(expression: "2+2", result: "4"), flags: []))
        #expect(board.string(forType: .string) == "4")
        #expect(rows.open(.calculator(expression: "2+", result: "", error: "Incomplete"), flags: []))
        #expect(rows.open(.calculator(expression: "", result: ""), flags: []))
        #expect(asked.all == ["hud: Copied 4", "leave", "hud: Incomplete", "hud: Nothing to copy yet"])
        #expect(board.string(forType: .string) == "4")
    }

    @Test func aRowThatIsNotFoundIsLeftToOthers() {
        #expect(!rows.open(.emojiSearch, flags: []))
        #expect(rows.returnTitle(for: .emojiSearch) == nil)
        #expect(rows.actions(for: .emojiSearch) == nil)
        #expect(asked.all.isEmpty)
    }
}
