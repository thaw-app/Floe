//
//  Shortcuts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Keyboard handling that doesn't need a window: list navigation steps and Raycast shortcut matching.
enum Shortcuts {
    /// ↑↓ move by one, Page Up/Down by a screenful, Home/End to the ends.
    static func navigationDelta(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 125: 1
        case 126: -1
        case 121: 9
        case 116: -9
        case 119: Int.max / 2
        case 115: -(Int.max / 2)
        default: nil
        }
    }

    /// Raycast's modifier names as AppKit flags; names it doesn't know are ignored.
    static func flags(_ modifiers: [String]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt", "alt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        return flags
    }

    /// The pressed key as Raycast names it, so an action's `{ key: "enter" }` answers to a pressed
    /// Return, whose characters are a carriage return and no letter at all. A key that is a letter
    /// or a mark is pressed as its own character.
    private static let namedKeys: [UInt16: String] = [
        36: "enter", 76: "enter", 48: "tab", 49: "space", 51: "backspace", 53: "escape", 117: "delete",
        123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end", 116: "pageUp", 121: "pageDown",
    ]

    static func pressed(_ event: NSEvent) -> String? {
        namedKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased()
    }

    /// The names written beside the canonical ones: Floe's own Shortcut constants say "arrowDown"
    /// where Raycast's docs say "down", and "return" and "esc" are other spellings of enter and escape.
    private static func canonical(_ key: String) -> String {
        switch key.lowercased() {
        case "arrowup": "up"
        case "arrowdown": "down"
        case "arrowleft": "left"
        case "arrowright": "right"
        case "return": "enter"
        case "esc": "escape"
        default: key.lowercased()
        }
    }

    /// Whether a pressed key, with its modifiers, is the action's `{ modifiers, key }` shortcut.
    static func matches(_ shortcut: Any?, key pressed: String?, flags: NSEvent.ModifierFlags) -> Bool {
        guard let shortcut = shortcut as? [String: Any], let key = shortcut["key"] as? String else { return false }
        return flags == Self.flags(shortcut["modifiers"] as? [String] ?? []) && Self.canonical(key) == pressed.map(Self.canonical)
    }

    /// A shortcut as an AppKit menu item takes it, which the menu draws at the end of the row.
    struct KeyEquivalent: Equatable {
        let key: String
        let flags: NSEvent.ModifierFlags
    }

    /// What AppKit draws for Raycast's named keys, by their canonical name. A menu takes Backspace as 0x08 and
    /// Forward Delete as 0x7F, which are not the characters a key-down event carries for them.
    private static let menuKeys: [String: String] = [
        "enter": "\r", "tab": "\t", "space": " ", "backspace": "\u{8}", "delete": "\u{8}", "escape": "\u{1b}",
        "deleteforward": "\u{7f}", "up": function(NSUpArrowFunctionKey), "down": function(NSDownArrowFunctionKey),
        "left": function(NSLeftArrowFunctionKey), "right": function(NSRightArrowFunctionKey), "home": function(NSHomeFunctionKey),
        "end": function(NSEndFunctionKey), "pageup": function(NSPageUpFunctionKey), "pagedown": function(NSPageDownFunctionKey),
    ]

    private static func function(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key)) ?? " "))
    }

    /// The `{ modifiers, key }` shortcut as a menu item's key equivalent; a key AppKit has no character for gives none.
    static func keyEquivalent(_ shortcut: Any?) -> KeyEquivalent? {
        guard let shortcut = shortcut as? [String: Any], let key = shortcut["key"] as? String else { return nil }
        let character = menuKeys[canonical(key)] ?? (key.count == 1 ? key.lowercased() : nil)
        return character.map { KeyEquivalent(key: $0, flags: flags(shortcut["modifiers"] as? [String] ?? [])) }
    }

    /// The shortcut as shown beside an action, such as ⌘⇧C.
    static func label(_ shortcut: Any?) -> String? {
        guard let shortcut = shortcut as? [String: Any], let key = shortcut["key"] as? String else { return nil }
        let symbols = ["cmd": "⌘", "shift": "⇧", "opt": "⌥", "alt": "⌥", "ctrl": "⌃"]
        let modifiers = (shortcut["modifiers"] as? [String] ?? []).compactMap { symbols[$0] }.joined()
        return modifiers + key.uppercased()
    }
}
