//
//  EmojiTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct EmojiTests {
    @Test func anEmptyTermListsRecentsByUseThenTheStandbys() {
        // The star and the fire are used equally; the star comes first in the table.
        let usage = ["❤": 5.0, "🔥": 1.0, "⭐": 1.0]
        let results = EmojiCatalog.search(term: "", frecency: { usage[$0] ?? 0 })
        #expect(results.map(\.character) == ["❤", "⭐", "🔥", "😀", "👍", "🎉", "✅", "❌"])
    }

    @Test func anEmptyTermKeepsToTheLimit() {
        let usage = ["❤": 5.0, "🔥": 1.0, "⭐": 1.0]
        #expect(EmojiCatalog.search(term: "", frecency: { usage[$0] ?? 0 }, limit: 2).map(\.character) == ["❤", "⭐"])
        #expect(EmojiCatalog.search(term: "", frecency: { _ in 0 }, limit: 3).map(\.character) == ["🔥", "❤", "😀"])
    }

    @Test func equalMatchesKeepTheTablesOrder() {
        // All four answer to the keyword "arrow" outright, so only their place in the table orders them.
        let arrows = EmojiCatalog.search(term: "arrow", frecency: { _ in 0 }, limit: 4)
        #expect(arrows.map(\.character) == ["←", "↑", "→", "↓"])
    }

    @Test func useLiftsAnEqualMatch() {
        let arrows = EmojiCatalog.search(term: "arrow", frecency: { $0 == "↓" ? 3 : 0 }, limit: 4)
        #expect(arrows.map(\.character) == ["↓", "←", "↑", "→"])
    }

    @Test(arguments: [
        ("\u{1F44B}", EmojiSkinTone.medium, "\u{1F44B}\u{1F3FD}"),
        ("\u{1F44D}", .dark, "\u{1F44D}\u{1F3FF}"),
        ("\u{261D}\u{FE0F}", .light, "\u{261D}\u{1F3FB}"),
        ("\u{1F469}\u{200D}\u{1F4BB}", .mediumDark, "\u{1F469}\u{1F3FE}\u{200D}\u{1F4BB}"),
    ])
    func aHandOrAPersonTakesTheTone(emoji: String, tone: EmojiSkinTone, toned: String) {
        #expect(tone.applied(to: emoji) == toned)
        #expect(toned.count == 1, "still one picture")
    }

    @Test(arguments: [
        "\u{1F600}", "\u{2764}\u{FE0F}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", "\u{1F44B}\u{1F3FB}", "A", "",
    ])
    func whatTakesNoToneOrMoreThanOneIsLeftAsItIs(emoji: String) {
        #expect(EmojiSkinTone.medium.applied(to: emoji) == emoji)
    }

    @Test func everyToneHasANameForThePicker() {
        #expect(EmojiSkinTone.allCases.map(\.label) == ["Default", "Light", "Medium-Light", "Medium", "Medium-Dark", "Dark"])
    }

    @Test func noToneChangesNothing() {
        #expect(EmojiSkinTone.none.applied(to: "\u{1F44B}") == "\u{1F44B}")
        #expect(EmojiSkinTone.allCases.map(\.rawValue) == ["none", "light", "mediumLight", "medium", "mediumDark", "dark"])
    }

    @Test func aTonedEmojiIsCountedAsTheSameEmoji() {
        let wave = EmojiResult(character: "\u{1F44B}", name: "waving hand")
        let toned = wave.toned(.medium)
        #expect(toned.character == "\u{1F44B}\u{1F3FD}")
        #expect(toned.id == wave.id)
        #expect(EmojiResult(character: "\u{1F600}", name: "grinning face").toned(.medium).untoned == nil)
    }
}
