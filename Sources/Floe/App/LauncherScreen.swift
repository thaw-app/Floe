//
//  LauncherScreen.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Which screen the launcher opens on: the one with the pointer, or one picked in Settings. A picked screen is named
/// by its display's UUID, which stays the same across restarts and reconnections, unlike its number or its place.
enum LauncherScreen {
    /// A display's UUID, or nil when macOS gives it none.
    static func identifier(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The screen to open on: the chosen one while it is connected, else the one with the pointer, else the main one.
    static func screen(chosen: String) -> NSScreen? {
        let screens = NSScreen.screens
        let index = choice(chosen: chosen, identifiers: screens.map(identifier(of:)), frames: screens.map(\.frame), pointer: NSEvent.mouseLocation)
        return index.map { screens[$0] } ?? NSScreen.main
    }

    /// The connected screens that can be picked, by identifier, with the name each is shown by.
    static func connected() -> [(id: String, name: String)] {
        named(NSScreen.screens.compactMap { screen in identifier(of: screen).map { ($0, screen.localizedName) } })
    }

    /// Two monitors of the same model share a name, so those are numbered in the order macOS lists them.
    static func named(_ screens: [(id: String, name: String)]) -> [(id: String, name: String)] {
        var seen: [String: Int] = [:]
        return screens.map { id, name in
            seen[name, default: 0] += 1
            let shared = screens.count { $0.name == name } > 1
            return (id, shared ? "\(name) \(seen[name] ?? 1)" : name)
        }
    }

    /// Which of the screens to open on, by their identifiers and frames; nil leaves it to the main screen.
    static func choice(chosen: String, identifiers: [String?], frames: [CGRect], pointer: CGPoint) -> Int? {
        if !chosen.isEmpty, let picked = identifiers.firstIndex(of: chosen) {
            return picked
        }
        return frames.firstIndex { $0.contains(pointer) }
    }
}
