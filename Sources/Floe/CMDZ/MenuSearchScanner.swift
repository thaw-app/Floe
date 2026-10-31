//
//  MenuSearchScanner.swift
//  Project: CMD-Z
//
//  Copyright (CMD-Z) © 2026 Toni Förster
//  CMD-Z by Toni Förster, https://github.com/stonerl/CMD-Z
//  Licensed under the MIT License
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Adapted for Floe from CMD-Z's MenuSearchScanner.swift: the shortcut keeps the virtual key and is shown
//  with Floe's key labels instead of SF Symbol names, the matching against a key event is left out, and
//  finding an item by its title or position is a function of its own, so it can be tested without Accessibility.
//  The walk reads each submenu's children once.
//  MenuEntry is called AppMenuItem here, since Floe has a MenuEntry of its own.

import ApplicationServices
import Carbon
import Cocoa
import ThawUI

/// The key equivalent of a menu item, as Accessibility reports it.
nonisolated struct MenuShortcut: Sendable, Equatable {
    let keyChar: String
    /// Carbon `MenuCommandModifiers` bits: 1=⇧, 2=⌥, 4=⌃, 8=no-⌘, 0x10=fn.
    let modifiers: Int
    let virtualKey: Int?

    /// The keys whose label is a glyph or a name rather than the character they type.
    private static let labelledKeys: Set<KeyCode> = [
        .returnKey, .keypadEnter, .tab, .space, .delete, .forwardDelete, .escape, .home, .end, .pageUp, .pageDown,
        .upArrow, .downArrow, .leftArrow, .rightArrow,
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
    ]

    /// The shortcut as a menu shows it, such as ⇧⌘E: fn, then ⌃⌥⇧⌘ in Apple's order, then the key.
    @MainActor var label: String {
        var modifierKeys: Modifiers = []
        if modifiers & 4 != 0 {
            modifierKeys.insert(.control)
        }
        if modifiers & 2 != 0 {
            modifierKeys.insert(.option)
        }
        if modifiers & 1 != 0 {
            modifierKeys.insert(.shift)
        }
        if modifiers & 8 == 0 {
            modifierKeys.insert(.command)
        }
        let function = modifiers & 0x10 != 0 ? KeyCode.function.stringValue : ""
        return function + modifierKeys.symbolicValue + key
    }

    @MainActor private var key: String {
        if let virtualKey, Self.labelledKeys.contains(KeyCode(rawValue: virtualKey)) {
            return KeyCode(rawValue: virtualKey).stringValue
        }
        switch keyChar {
        case AXGlyph.globe: return KeyCode.function.stringValue
        case AXGlyph.microphone: return "\u{1F3A4}"
        case "\u{7F}": return KeyCode.forwardDelete.stringValue
        default: return keyChar.uppercased()
        }
    }
}

/// Character values the Accessibility API uses for key glyphs.
nonisolated enum AXGlyph {
    static let globe = "\u{1F310}" // globe / function key
    static let microphone = "\u{1F3A4}" // dictation key
}

/// A single searchable menu item, represented as Sendable value types so it can cross actors.
nonisolated struct AppMenuItem: Sendable, Equatable {
    let title: String
    let path: [String]
    let indices: [Int]
    let shortcut: MenuShortcut?
    let enabled: Bool

    var displayPath: String {
        path.joined(separator: " > ")
    }

    var pathKey: String {
        zip(path, indices).map { "\($0)\u{2}\($1)" }.joined(separator: "\u{1}")
    }
}

/// Reads and triggers the frontmost application's menu bar via the Accessibility API.
/// All methods are synchronous and blocking (AX XPC), so call them off the main actor.
nonisolated enum MenuSearchScanner {
    private static let walkBudget: TimeInterval = 1.0
    private static let sweepTimeout: Float = 0.2

    /// Recursively walks the menu bar of `pid` and returns a flat list of leaf menu items.
    static func entries(for pid: pid_t) -> [AppMenuItem] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        guard let menuBar = element(app, kAXMenuBarAttribute) else {
            return []
        }

        var result: [AppMenuItem] = []
        let deadline = Date().addingTimeInterval(walkBudget)

        // Skip the global Apple menu (AX reports its title as "Apple").
        for (index, item) in children(of: menuBar).enumerated() {
            guard let raw = string(item, kAXTitleAttribute), !raw.isEmpty, raw != "Apple" else {
                continue
            }
            let title = normalizeTitle(raw)
            walk(flattenedChildren(of: item), path: [title], indices: [index], deadline: deadline, into: &result)
        }
        return result
    }

    /// Triggers the menu item at `path` by resolving its leaf element and pressing it directly.
    static func trigger(path: [String], indices: [Int], pid: pid_t) -> Bool {
        Thread.sleep(forTimeInterval: 0.15)

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        guard let menuBar = element(app, kAXMenuBarAttribute) else {
            return false
        }

        guard indices.count == path.count else {
            return false
        }

        var items = children(of: menuBar)
        var leaf: AXUIElement?
        for (level, title) in path.enumerated() {
            let match = item(titled: title, at: indices[level], in: items) { normalizeTitle(string($0, kAXTitleAttribute) ?? "") }
            guard let match else {
                return false
            }
            leaf = match
            if level < path.count - 1 {
                items = flattenedChildren(of: match)
            }
        }

        guard let leaf else {
            return false
        }
        return AXUIElementPerformAction(leaf, kAXPressAction as CFString) == .success
    }

    /// The item at `index` when it still has the title; else the first with the title, since an app may
    /// have added or removed items since the walk.
    static func item<Item>(titled title: String, at index: Int, in items: [Item], title titleOf: (Item) -> String) -> Item? {
        if items.indices.contains(index), titleOf(items[index]) == title {
            return items[index]
        }
        return items.first { titleOf($0) == title }
    }

    // MARK: - Walk

    /// Each submenu's children are read once: every read is a round trip to the app.
    private static func walk(
        _ children: [AXUIElement],
        path: [String],
        indices: [Int],
        deadline: Date,
        into entries: inout [AppMenuItem]
    ) {
        guard Date() < deadline else { return }

        for (childIndex, child) in children.enumerated() {
            guard Date() < deadline else { return }
            AXUIElementSetMessagingTimeout(child, sweepTimeout)

            let title = normalizeTitle(string(child, kAXTitleAttribute) ?? "")
            let nested = flattenedChildren(of: child)

            if nested.isEmpty {
                if !title.isEmpty {
                    entries.append(AppMenuItem(
                        title: title,
                        path: path + [title],
                        indices: indices + [childIndex],
                        shortcut: shortcut(for: child),
                        enabled: bool(child, kAXEnabledAttribute) ?? true
                    ))
                }
            } else {
                walk(nested, path: path + [title], indices: indices + [childIndex], deadline: deadline, into: &entries)
            }
        }
    }

    // MARK: - Shortcut

    private static func shortcut(for element: AXUIElement) -> MenuShortcut? {
        guard let char = string(element, kAXMenuItemCmdCharAttribute), !char.isEmpty else {
            return nil
        }
        let modifiers = (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        let virtualKey = (attribute(element, kAXMenuItemCmdVirtualKeyAttribute) as? NSNumber)?.intValue
        return MenuShortcut(keyChar: char, modifiers: modifiers, virtualKey: virtualKey)
    }

    // MARK: - AX primitives

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func normalizeTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        attribute(element, name) as? Bool
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// Returns children with empty-title containers (AXMenu) collapsed away.
    private static func flattenedChildren(of element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        for child in children(of: element) {
            let title = string(child, kAXTitleAttribute) ?? ""
            if title.isEmpty, !children(of: child).isEmpty {
                result.append(contentsOf: children(of: child))
            } else {
                result.append(child)
            }
        }
        return result
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // The type was checked just above.
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
