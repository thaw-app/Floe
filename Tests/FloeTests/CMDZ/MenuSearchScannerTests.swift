//
//  MenuSearchScannerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

@MainActor struct MenuSearchScannerTests {
    private func shortcut(_ key: String, _ modifiers: Int = 0, virtualKey: Int? = nil) -> MenuShortcut {
        MenuShortcut(keyChar: key, modifiers: modifiers, virtualKey: virtualKey)
    }

    @Test func aShortcutReadsAsAMenuShowsItWithTheModifiersInApplesOrder() {
        #expect(shortcut("e").label == "⌘E", "Command is there unless the no-Command bit says otherwise")
        #expect(shortcut("e", 1).label == "⇧⌘E")
        #expect(shortcut("e", 1 | 2 | 4).label == "⌃⌥⇧⌘E")
        #expect(shortcut("q", 2).label == "⌥⌘Q")
        #expect(shortcut("x", 4 | 8).label == "⌃X", "the no-Command bit leaves ⌘ out")
        #expect(shortcut("f", 0x10).label == "🌐\u{FE0E}⌘F", "fn comes first")
    }

    @Test func aKeyWithAGlyphIsShownByItAndNotByWhatItTypes() {
        #expect(shortcut("\r", virtualKey: 36).label == "⌘⏎")
        #expect(shortcut("\u{1C}", 8, virtualKey: 123).label == "←")
        #expect(shortcut("\u{F708}", 8, virtualKey: 96).label == "F5")
        #expect(shortcut("\u{7F}").label == "⌘⌦")
        #expect(shortcut(AXGlyph.globe, 8).label == "🌐\u{FE0E}")
        #expect(shortcut("e", virtualKey: 14).label == "⌘E", "a letter's virtual key changes nothing")
    }

    @Test func anItemIsFoundAtItsPlaceWhileItKeepsItsTitle() {
        let titles = ["New", "Open…", "Close"]
        #expect(MenuSearchScanner.item(titled: "Open…", at: 1, in: titles) { $0 } == "Open…")
    }

    @Test func anItemThatMovedIsFoundByItsTitleAndOneThatWentIsNot() {
        let items = [(0, "New"), (1, "Open Recent"), (2, "Open…"), (3, "Open…")]
        let moved = MenuSearchScanner.item(titled: "Open…", at: 1, in: items) { $0.1 }
        #expect(moved?.0 == 2, "the first item with the title, since the app added one above it")
        #expect(MenuSearchScanner.item(titled: "Open…", at: 9, in: items) { $0.1 }?.0 == 2, "a place past the end too")
        #expect(MenuSearchScanner.item(titled: "Print…", at: 0, in: items) { $0.1 } == nil)
    }

    @Test func anItemKnowsItsMenusAndAKeyThatTellsItFromATwin() {
        let export = AppMenuItem(title: "PDF…", path: ["File", "Export", "PDF…"], indices: [1, 7, 0], shortcut: nil, enabled: true)
        let twin = AppMenuItem(title: "PDF…", path: ["File", "Export", "PDF…"], indices: [1, 7, 3], shortcut: nil, enabled: true)
        #expect(export.displayPath == "File > Export > PDF…")
        #expect(export.menuPath == "File > Export")
        #expect(export.id != twin.id, "the places tell two items with one path apart")
        let top = AppMenuItem(title: "Help", path: ["Help"], indices: [5], shortcut: nil, enabled: true)
        #expect(top.menuPath.isEmpty)
    }
}
