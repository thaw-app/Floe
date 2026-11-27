//
//  HotkeyRegistryTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Carbon.HIToolbox
@testable import Floe
import Testing

struct HotkeyRegistryTests {
    private let control = UInt32(controlKey)
    private let option = UInt32(optionKey)

    @Test func aHotkeyFiresOnItsOwnModifiers() {
        #expect(!HotkeyRegistry.holdsExtraModifier(control, beyond: control))
        #expect(!HotkeyRegistry.holdsExtraModifier(control | option, beyond: control | option))
    }

    @Test func anExtraModifierLeavesTheKeysToMacOS() {
        #expect(HotkeyRegistry.holdsExtraModifier(control | option, beyond: control), "Control-Option-Space switches input sources")
        #expect(HotkeyRegistry.holdsExtraModifier(control | option, beyond: option))
        #expect(HotkeyRegistry.holdsExtraModifier(control | UInt32(cmdKey), beyond: control))
    }

    @Test func aModifierLetGoEarlyStillFires() {
        #expect(!HotkeyRegistry.holdsExtraModifier(0, beyond: control), "a quick tap can lift Control before the hotkey arrives")
    }

    @Test func capsLockAndTheMouseButtonDoNotCount() {
        #expect(!HotkeyRegistry.holdsExtraModifier(control | UInt32(alphaLock) | UInt32(btnState), beyond: control))
    }
}
