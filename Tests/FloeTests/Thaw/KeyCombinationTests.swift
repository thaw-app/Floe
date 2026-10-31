//
//  KeyCombinationTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Carbon.HIToolbox
@testable import Floe
import Testing
import ThawUI

struct ModifiersTests {
    private static nonisolated let single: [(Modifiers, NSEvent.ModifierFlags, CGEventFlags, Int, String)] = [
        (.control, .control, .maskControl, controlKey, "⌃"),
        (.option, .option, .maskAlternate, optionKey, "⌥"),
        (.shift, .shift, .maskShift, shiftKey, "⇧"),
        (.command, .command, .maskCommand, cmdKey, "⌘"),
    ]

    @Test(arguments: single)
    func eachModifierConvertsToAndFromEverySystemRepresentation(
        modifier: Modifiers,
        appKit: NSEvent.ModifierFlags,
        coreGraphics: CGEventFlags,
        carbon: Int,
        symbol: String
    ) {
        #expect(modifier.nsEventFlags == appKit)
        #expect(modifier.cgEventFlags == coreGraphics)
        #expect(modifier.carbonFlags == carbon)
        #expect(modifier.symbolicValue == symbol)
        #expect(Modifiers(nsEventFlags: appKit) == modifier)
        #expect(Modifiers(cgEventFlags: coreGraphics) == modifier)
        #expect(Modifiers(carbonFlags: carbon) == modifier)
    }

    @Test func combinationsRoundTripAndPrintInSystemOrder() {
        let all: Modifiers = [.command, .shift, .option, .control]
        #expect(all.symbolicValue == "⌃⌥⇧⌘")
        #expect(Modifiers(nsEventFlags: all.nsEventFlags) == all)
        #expect(Modifiers(cgEventFlags: all.cgEventFlags) == all)
        #expect(Modifiers(carbonFlags: all.carbonFlags) == all)
        #expect(Modifiers.canonicalOrder == [.control, .option, .shift, .command])
    }

    @Test func flagsThatAreNotModifiersAreIgnored() {
        #expect(Modifiers(nsEventFlags: [.capsLock, .function, .numericPad]).isEmpty)
        #expect(Modifiers(carbonFlags: 0).isEmpty)
        #expect(Modifiers().symbolicValue.isEmpty)
    }
}

struct KeyCodeTests {
    @Test(arguments: [(KeyCode.space, "Space"), (.returnKey, "⏎"), (.escape, "⎋"), (.upArrow, "↑"), (.f1, "F1")])
    func keysWithAPrintedGlyphUseIt(key: KeyCode, label: String) {
        #expect(key.stringValue == label)
    }

    @Test func keypadKeysAreTheirDigitInsideAKeycap() {
        #expect(Array(KeyCode.keypad0.stringValue.unicodeScalars) == ["0", "\u{20E3}"])
    }

    @Test func rawValuesAreVirtualKeyCodes() {
        #expect(KeyCode.space.rawValue == kVK_Space)
        #expect(KeyCode(rawValue: kVK_ANSI_A) == .a)
    }

    @Test func keysWithoutAPrintedGlyphShowWhatTheyTypeOnTheCurrentLayout() {
        #expect(KeyCode.a.stringValue == KeyCode.a.keyEquivalent)
        #expect(KeyCode.a.keyEquivalent.count == 1)
    }
}

struct KeyCombinationTests {
    private let combination = KeyCombination(key: .space, modifiers: [.control, .option])

    @Test func displayValueShowsModifiersThenTheKey() {
        #expect(combination.displayValue == "⌃⌥ Space")
    }

    @Test func encodesAsAPairOfRawValuesAndDecodesBack() throws {
        let data = try JSONEncoder().encode(combination)
        #expect(String(decoding: data, as: UTF8.self) == "[\(kVK_Space),3]")
        #expect(try JSONDecoder().decode(KeyCombination.self, from: data) == combination)
    }

    @Test(arguments: ["[49]", "[49,3,1]", "[]"])
    func decodingRejectsAnythingButAPair(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination.self, from: Data(json.utf8))
        }
    }

    @Test func equalCombinationsHashAlike() {
        let same = KeyCombination(key: .space, modifiers: [.option, .control])
        #expect(same == combination)
        #expect(Set([same, combination]).count == 1)
        #expect(KeyCombination(key: .space, modifiers: .command) != combination)
    }

    @Test func buildsFromAKeyEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "K",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_K)
        ))
        #expect(KeyCombination(event: event) == KeyCombination(key: .k, modifiers: [.command, .shift]))
    }

    @Test func aCombinationNoOneWouldReserveIsNotSystemReserved() {
        #expect(KeyCombination(key: .f1, modifiers: [.control, .option, .shift, .command]).isSystemReserved == false)
    }
}
