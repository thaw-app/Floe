//
//  ShortcutsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct ShortcutsTests {
    @Test(arguments: [(125, 1), (126, -1), (121, 9), (116, -9)] as [(UInt16, Int)])
    func arrowAndPageKeysMoveTheSelection(keyCode: UInt16, delta: Int) {
        #expect(Shortcuts.navigationDelta(keyCode) == delta)
    }

    @Test func homeAndEndJumpFarEnoughToReachEitherEndWithoutOverflowing() throws {
        let end = try #require(Shortcuts.navigationDelta(119))
        let home = try #require(Shortcuts.navigationDelta(115))
        #expect(end > 1_000_000)
        #expect(home < -1_000_000)
        #expect(ViewState.clamp(5 + end, count: 10) == 9)
        #expect(ViewState.clamp(5 + home, count: 10) == 0)
    }

    @Test(arguments: [36, 53, 40, 0] as [UInt16])
    func otherKeysAreNotNavigation(keyCode: UInt16) {
        #expect(Shortcuts.navigationDelta(keyCode) == nil)
    }

    @Test func modifierNamesMapToFlags() {
        #expect(Shortcuts.flags(["cmd", "shift"]) == [.command, .shift])
        #expect(Shortcuts.flags(["opt"]) == .option)
        #expect(Shortcuts.flags(["alt"]) == .option)
        #expect(Shortcuts.flags(["ctrl"]) == .control)
        #expect(Shortcuts.flags(["hyper"]).isEmpty)
        #expect(Shortcuts.flags([]).isEmpty)
    }

    @Test func aShortcutMatchesItsKeyWithExactlyItsModifiers() {
        let copy: [String: Any] = ["modifiers": ["cmd", "shift"], "key": "c"]
        #expect(Shortcuts.matches(copy, key: "c", flags: [.command, .shift]))
        #expect(Shortcuts.matches(copy, key: "C", flags: [.command, .shift]), "the key is compared without regard to case")
        #expect(Shortcuts.matches(copy, key: "c", flags: .command) == false)
        #expect(Shortcuts.matches(copy, key: "c", flags: [.command, .shift, .option]) == false)
        #expect(Shortcuts.matches(copy, key: "x", flags: [.command, .shift]) == false)
        #expect(Shortcuts.matches(copy, key: nil, flags: [.command, .shift]) == false)
    }

    @Test func namedKeysArePressedByTheirKeyCodeNotTheirCharacters() {
        // Return's characters are a carriage return, so the key an action declares is the name it is
        // matched by, and the names of the rest come from their key codes the same way.
        func pressed(_ keyCode: UInt16, characters: String = "\r", flags: NSEvent.ModifierFlags = []) -> String? {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            )
            guard let event else { return nil }
            return Shortcuts.pressed(event)
        }
        #expect(pressed(36) == "enter")
        #expect(pressed(76) == "enter", "the keypad's Return is Enter too")
        #expect(pressed(125) == "down")
        #expect(pressed(48) == "tab")
        #expect(pressed(51) == "backspace")
        #expect(pressed(53) == "escape")
        // A key that is a letter is pressed as that letter, with no modifiers in its name.
        #expect(pressed(8, characters: "c", flags: .command) == "c")
    }

    @Test func enterShortcutsMatchTheirModifiersAndTheNamesWrittenBesideRaycasts() {
        let fill: [String: Any] = ["modifiers": ["shift"], "key": "enter"]
        #expect(Shortcuts.matches(fill, key: "enter", flags: .shift))
        #expect(Shortcuts.matches(fill, key: "enter", flags: []) == false, "a bare Return is the main action, not this one")
        #expect(Shortcuts.matches(fill, key: "enter", flags: .control) == false)
        let fillWithControl: [String: Any] = ["modifiers": ["ctrl"], "key": "enter"]
        #expect(Shortcuts.matches(fillWithControl, key: "enter", flags: .control))
        // The names Floe's own Shortcut constants use, and Raycast's other spellings.
        #expect(Shortcuts.matches(["modifiers": ["cmd"], "key": "arrowDown"], key: "down", flags: .command))
        #expect(Shortcuts.matches(["modifiers": ["cmd"], "key": "return"], key: "enter", flags: .command))
        #expect(Shortcuts.matches(["modifiers": ["cmd"], "key": "esc"], key: "escape", flags: .command))
    }

    @Test func aShortcutWithoutModifiersMatchesTheBareKey() {
        #expect(Shortcuts.matches(["key": "r"], key: "r", flags: []))
    }

    @Test(arguments: [nil, "cmd+c", ["modifiers": ["cmd"]]] as [(any Sendable)?])
    func malformedShortcutsNeverMatchAndHaveNoLabel(shortcut: (any Sendable)?) {
        #expect(Shortcuts.matches(shortcut, key: "c", flags: .command) == false)
        #expect(Shortcuts.label(shortcut) == nil)
    }

    @Test func labelsShowModifierSymbolsThenTheKey() {
        #expect(Shortcuts.label(["modifiers": ["cmd", "shift"], "key": "c"]) == "⌘⇧C")
        #expect(Shortcuts.label(["modifiers": ["ctrl", "opt"], "key": "x"]) == "⌃⌥X")
        #expect(Shortcuts.label(["modifiers": ["alt", "unknown"], "key": "k"]) == "⌥K")
        #expect(Shortcuts.label(["key": "r"]) == "R")
    }

    @Test func menuKeyEquivalentsUseAppKitsCharacters() {
        #expect(Shortcuts.keyEquivalent(["modifiers": ["cmd", "shift"], "key": "C"]) == .init(key: "c", flags: [.command, .shift]))
        #expect(Shortcuts.keyEquivalent(["modifiers": ["opt"], "key": "return"]) == .init(key: "\r", flags: .option))
        #expect(Shortcuts.keyEquivalent(["modifiers": [], "key": "arrowUp"])?.key == String(utf16CodeUnits: [UInt16(NSUpArrowFunctionKey)], count: 1))
        #expect(Shortcuts.keyEquivalent(["modifiers": ["ctrl"], "key": "deleteForward"])?.key == String(utf16CodeUnits: [UInt16(NSDeleteFunctionKey)], count: 1))
        #expect(Shortcuts.keyEquivalent(["modifiers": ["cmd"], "key": "backspace"])?.key == "\u{8}")
        #expect(Shortcuts.keyEquivalent(["modifiers": ["cmd"], "key": "f13"]) == nil, "a name AppKit has no character for")
        #expect(Shortcuts.keyEquivalent(["modifiers": ["cmd"]]) == nil)
        #expect(Shortcuts.keyEquivalent(nil) == nil)
    }
}
