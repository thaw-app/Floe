//
//  EmojiRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// Emoji as a row owner: copied onto a pasteboard of their own, and Command-V pressed by a stand-in.
@MainActor
final class EmojiRowsTests {
    private let board = NSPasteboard.withUniqueName()
    private let asked = CallLog()
    private let rows = EmojiRows()
    private let wave = EmojiResult(character: "👋", name: "waving hand")

    init() {
        let asked = asked
        rows.pasteboard = board
        rows.host = RowHost(showHUD: { asked.note("hud: \($0)") }, leave: { asked.note("leave") })
        rows.recordUse = { asked.note("use: \($0)") }
        rows.pressPaste = { asked.note("paste") }
    }

    isolated deinit {
        board.releaseGlobally()
    }

    @Test func commandReturnOnlyCopiesTheEmoji() {
        rows.canPaste = { true }
        #expect(rows.open(.emoji(wave), flags: .command))
        #expect(board.string(forType: .string) == "👋")
        #expect(asked.all == ["use: \(wave.id)", "hud: Copied 👋"])
    }

    @Test func returnWithoutAccessibilityCopiesAndSaysSo() {
        rows.canPaste = { false }
        #expect(rows.open(.emoji(wave), flags: []))
        #expect(board.string(forType: .string) == "👋")
        #expect(asked.all == ["use: \(wave.id)", "hud: Copied"])
    }

    @Test func returnWithAccessibilityLeavesThenPastes() async {
        rows.canPaste = { true }
        #expect(rows.open(.emoji(wave), flags: []))
        #expect(asked.all == ["use: \(wave.id)", "leave"])
        for _ in 0 ..< 1000 where !asked.all.contains("paste") {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(asked.all.last == "paste")
    }

    @Test func aRowThatIsNotAnEmojiIsLeftToOthers() {
        #expect(!rows.open(.emojiSearch, flags: []))
        #expect(rows.returnTitle(for: .emoji(wave)) == nil)
        #expect(asked.all.isEmpty)
    }
}
