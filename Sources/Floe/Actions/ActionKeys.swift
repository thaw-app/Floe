//
//  ActionKeys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ThawUI
import UniformTypeIdentifiers

/// The kinds of result whose Actions menu rows have keys of their own.
nonisolated enum SubjectKind: String, CaseIterable, Sendable {
    case app
    case file
    case folder
    case url

    /// The kind of a result, or nil for one that has none, such as a command. A file is read where it is now:
    /// an app found as a file is an app, a link to a folder is a folder, and a file that is gone is nothing.
    static func of(_ item: RootItem) -> SubjectKind? {
        switch item {
        case .app: .app
        case let .file(file): of(file.url)
        // A browser's tab is switched to, not opened, so it is not a link.
        case .webAddress, .bookmark: .url
        default: nil
        }
    }

    static func of(_ url: URL) -> SubjectKind? {
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        guard let values else { return nil }
        if values.contentType?.conforms(to: .application) == true {
            return .app
        }
        return values.isDirectory == true && values.isPackage != true ? .folder : .file
    }
}

/// The keys that run rows of an Actions menu while their result is selected, by the row's id. The menu draws them
/// beside the rows, the views run the row whose keys are pressed, and the bottom bars' hints read them here.
struct ActionKeys: Equatable {
    private(set) var keys: [ActionID: KeyCombination]

    /// Floe's own keys on a kind of result, or with nil on a result that has none, such as a command. Files and
    /// folders share theirs, and an app has them too: one found by Search Files has a file's rows. A letter is the
    /// key that types it on the layout, as the main menu's keys are.
    static func floe(for kind: SubjectKind?, on layout: KeyLayout = .current) -> ActionKeys {
        switch kind {
        case .file, .folder: ActionKeys(keys: files(on: layout))
        case .app: ActionKeys(keys: files(on: layout).merging(favorite(on: layout)) { $1 })
        case .url: ActionKeys(keys: [:])
        case nil: ActionKeys(keys: favorite(on: layout))
        }
    }

    private static func favorite(on layout: KeyLayout) -> [ActionID: KeyCombination] {
        [.toggleFavorite: KeyCombination(key: layout.key(typing: "f"), modifiers: [.command, .shift])]
    }

    private static func files(on layout: KeyLayout) -> [ActionID: KeyCombination] {
        [
            .showInFinder: KeyCombination(key: .returnKey, modifiers: .command),
            .quickLook: KeyCombination(key: layout.key(typing: "y"), modifiers: .command),
            .copyPath: KeyCombination(key: layout.key(typing: "c"), modifiers: [.command, .shift]),
        ]
    }

    func key(for id: ActionID) -> KeyCombination? {
        keys[id]
    }

    /// The rows with their keys set, a submenu's rows included. A row is given keys by its id, so a row without one
    /// has none.
    func keyed(_ rows: [ItemAction?]) -> [ItemAction?] {
        rows.map { $0.map(withKeys) }
    }

    private func withKeys(_ row: ItemAction) -> ItemAction {
        var row = row
        row.shortcut = row.id.flatMap { keys[$0] }
        row.children = row.children.map(withKeys)
        return row
    }

    /// The row the keys run: the first in menu order, a submenu's rows included, whose id has them.
    func row(for pressed: KeyCombination, in rows: [ItemAction?]) -> ItemAction? {
        for case let row? in rows {
            if let id = row.id, keys[id] == pressed {
                return row
            }
            if let child = self.row(for: pressed, in: row.children) {
                return child
            }
        }
        return nil
    }

    /// A view's key as a combination. Enter on the keypad is Return, as the views read it.
    static func pressed(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> KeyCombination {
        KeyCombination(key: keyCode == 76 ? .returnKey : KeyCode(rawValue: Int(keyCode)), modifiers: Modifiers(nsEventFlags: flags))
    }

    /// Runs the row the pressed keys belong to. True when they were a row's keys, whether the row ran or not;
    /// false leaves them to the view. Every row's keys have Command, so what is typed into a search never reads a
    /// file's kind (`keys`) or builds a row (`rows`).
    static func handle(_ pressed: KeyCombination, keys: () -> ActionKeys, rows: () -> [ItemAction?], collapsed: Bool = false) -> Bool {
        guard pressed.modifiers.contains(.command) else { return false }
        let keys = keys()
        guard keys.keys.values.contains(pressed) else { return false }
        // Collapsed, the selected row is not on screen.
        if collapsed {
            return true
        }
        if let row = keys.row(for: pressed, in: rows()) {
            row.run()
            return true
        }
        // A kind's keys are the view's even where the result lacks the row, so they are never typed into the
        // search. Return with them held still does what Return does.
        return pressed.key != .returnKey
    }
}

extension KeyCombination {
    /// What a menu item draws for these keys: Return and a function key as themselves on any layout, any other key
    /// as what it types. A keypad key types a digit or a mark, and the keypad's modifier tells it from the main row's.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        let modifiers = modifiers.nsEventFlags
        if key == .returnKey {
            return ("\r", modifiers)
        }
        if let position = Self.functionRow.firstIndex(of: key) {
            return (String(utf16CodeUnits: [unichar(NSF1FunctionKey + position)], count: 1), modifiers)
        }
        return (key.keyEquivalent.lowercased(), Self.keypad.contains(key) ? modifiers.union(.numericPad) : modifiers)
    }

    private static let functionRow: [KeyCode] = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
    ]

    private static let keypad: Set<KeyCode> = [
        .keypad0, .keypad1, .keypad2, .keypad3, .keypad4, .keypad5, .keypad6, .keypad7, .keypad8, .keypad9,
        .keypadDecimal, .keypadPlus, .keypadMinus, .keypadMultiply, .keypadDivide, .keypadEquals,
    ]
}

/// What each key types on a keyboard layout: the one the Mac types with now, or a fixed one in a test. Floe names its
/// letter keys by what they type, so ⌘Y is the key that types y on a German keyboard too, and ⌘Z stays Undo there.
struct KeyLayout {
    let text: (KeyCode) -> String

    static var current: KeyLayout {
        KeyLayout { $0.keyEquivalent }
    }

    /// The key that types the character with no modifier held, or its key on a US keyboard where no key does.
    func key(typing character: Character) -> KeyCode {
        let us = Self.us[character] ?? .space
        if text(us) == String(character) {
            return us
        }
        return Self.us.values.sorted { $0.rawValue < $1.rawValue }.first { text($0) == String(character) } ?? us
    }

    /// The keys that type a letter, a digit or a mark on a US keyboard, by what they type there. On other layouts
    /// these same keys type the other letters and marks.
    static let us: [Character: KeyCode] = [
        "a": .a, "b": .b, "c": .c, "d": .d, "e": .e, "f": .f, "g": .g, "h": .h, "i": .i, "j": .j, "k": .k, "l": .l,
        "m": .m, "n": .n, "o": .o, "p": .p, "q": .q, "r": .r, "s": .s, "t": .t, "u": .u, "v": .v, "w": .w, "x": .x,
        "y": .y, "z": .z, "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four, "5": .five, "6": .six,
        "7": .seven, "8": .eight, "9": .nine, "`": .grave, "-": .minus, "=": .equal, "[": .leftBracket,
        "]": .rightBracket, "\\": .backslash, ";": .semicolon, "'": .quote, ",": .comma, ".": .period, "/": .slash,
    ]
}
