//
//  KeywordBufferTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
@testable import Floe
import Testing

nonisolated struct KeywordBufferTests {
    private static let returnKey: CGKeyCode = 36
    private static let tab: CGKeyCode = 48
    private static let escape: CGKeyCode = 53
    private static let keypadEnter: CGKeyCode = 76
    private static let delete: CGKeyCode = 51
    private static let forwardDelete: CGKeyCode = 117
    private static let home: CGKeyCode = 115
    private static let end: CGKeyCode = 119
    private static let pageUp: CGKeyCode = 116
    private static let pageDown: CGKeyCode = 121
    private static let arrows: [CGKeyCode] = [123, 124, 125, 126]
    private static let letterA: CGKeyCode = 0
    private static let f5: CGKeyCode = 96

    /// Types each character as its own key press, the way the tap hears them, and returns the last text to match.
    @discardableResult
    private func type(_ characters: String, into keys: inout KeywordBuffer, flags: CGEventFlags = []) -> String? {
        var last: String?
        for character in characters {
            let key = KeywordBuffer.key(code: Self.letterA, flags: flags, characters: String(character))
            last = key.flatMap { keys.take($0) }
        }
        return last
    }

    private func press(_ code: CGKeyCode, characters: String? = nil, into keys: inout KeywordBuffer) -> String? {
        KeywordBuffer.key(code: code, flags: [], characters: characters).flatMap { keys.take($0) }
    }

    @Test func eachTypedKeyIsRememberedAndOffered() throws {
        var keys = KeywordBuffer()
        var offered: [String] = []
        for character in ";sig" {
            let key = try #require(KeywordBuffer.key(code: Self.letterA, flags: [], characters: String(character)))
            let text = keys.take(key)
            try offered.append(#require(text))
        }
        #expect(keys.text == ";sig")
        #expect(offered == [";", ";s", ";si", ";sig"])
    }

    @Test func backspaceRemovesTheLastCharacterAndOffersNothing() {
        var keys = KeywordBuffer()
        type(";sx", into: &keys)
        #expect(press(Self.delete, characters: "\u{7F}", into: &keys) == nil)
        #expect(keys.text == ";s")
        #expect(!keys.text.contains("\u{7F}"))

        type("igx", into: &keys)
        #expect(press(Self.delete, characters: "\u{7F}", into: &keys) == nil)
        #expect(keys.text == ";sig")
    }

    @Test func backspaceOnNothingLeavesNothing() {
        var keys = KeywordBuffer()
        #expect(press(Self.delete, characters: "\u{7F}", into: &keys) == nil)
        #expect(keys.text.isEmpty)
    }

    @Test(arguments: [returnKey, tab, escape, keypadEnter, home, end, pageUp, pageDown, forwardDelete] + arrows)
    func aKeyThatMovesTheCaretForgetsTheWord(code: CGKeyCode) {
        var keys = KeywordBuffer()
        type(";si", into: &keys)
        #expect(press(code, characters: "x", into: &keys) == nil)
        #expect(keys.text.isEmpty)
    }

    @Test(arguments: [CGEventFlags.maskCommand, .maskControl, .maskAlternate])
    func aShortcutForgetsTheWord(flag: CGEventFlags) {
        var keys = KeywordBuffer()
        type(";si", into: &keys)
        #expect(type("g", into: &keys, flags: flag) == nil)
        #expect(keys.text.isEmpty)
    }

    @Test func shiftAloneStillTypes() {
        var keys = KeywordBuffer()
        #expect(type(":", into: &keys, flags: .maskShift) == ":")
        #expect(keys.text == ":")
    }

    @Test func aDeadKeyChangesNothing() {
        var keys = KeywordBuffer()
        type(";s", into: &keys)
        #expect(KeywordBuffer.key(code: Self.letterA, flags: [], characters: nil) == nil)
        #expect(KeywordBuffer.key(code: Self.letterA, flags: [], characters: "") == nil)
        #expect(keys.text == ";s")
    }

    @Test(arguments: ["\u{F708}", "\u{1B}", "\u{0}"])
    func aFunctionKeyOrControlCharacterForgetsTheWord(characters: String) {
        var keys = KeywordBuffer()
        type(";s", into: &keys)
        #expect(press(Self.f5, characters: characters, into: &keys) == nil)
        #expect(keys.text.isEmpty)
    }

    @Test func onlyTheLastThirtyTwoCharactersAreKept() {
        var keys = KeywordBuffer()
        let typed = (0 ..< 40).map { String(UnicodeScalar(UInt8(65 + $0 % 26))) }.joined()
        type(typed, into: &keys)
        #expect(keys.text.count == KeywordBuffer.maxLength)
        #expect(keys.text == String(typed.suffix(32)))
    }

    @Test func clearForgetsEverything() {
        var keys = KeywordBuffer()
        type(";si", into: &keys)
        keys.clear()
        #expect(keys.text.isEmpty)
    }

    @MainActor @Test func aKeywordSplitByAClickDoesNotMatch() {
        let snippet = Snippet(name: "Signature", keyword: ";sig", text: "Best,\nOwen")
        var keys = KeywordBuffer()
        type(";s", into: &keys)
        keys.clear()
        let text = type("ig", into: &keys)
        #expect(text == "ig")
        #expect(Snippet.match(typed: text ?? "", in: [snippet]) == nil)
    }
}
