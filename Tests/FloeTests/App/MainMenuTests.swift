//
//  MainMenuTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor
struct MainMenuTests {
    private final class Target: NSObject {
        @objc func about() {}
        @objc func settings() {}
    }

    @Test func residentOmitsTheWindowSubmenuAndItsRegistration() {
        let app = NSApplication.shared
        let previous = app.windowsMenu
        let target = Target()
        let menu = MainMenu.make(target: target, about: #selector(Target.about), settings: #selector(Target.settings), includesWindowMenu: false)

        #expect(app.windowsMenu === previous, "the resident does not register a Window menu")
        #expect(menu.items.compactMap(\.submenu).count == 2)
        let commands = menu.items.compactMap(\.submenu).flatMap(\.items)
        #expect(!commands.contains { $0.action == #selector(NSWindow.performClose) })
        #expect(!commands.contains { $0.action == #selector(NSWindow.performMiniaturize) })
    }

    @Test func foregroundAndSettingsKeepWindowCommandsByDefault() throws {
        let app = NSApplication.shared
        let previous = app.windowsMenu
        defer { app.windowsMenu = previous }
        let target = Target()
        let menu = MainMenu.make(target: target, about: #selector(Target.about), settings: #selector(Target.settings))
        let windows = try #require(app.windowsMenu)

        #expect(menu.items.contains { $0.submenu === windows })
        #expect(windows.items.contains { $0.action == #selector(NSWindow.performClose) && $0.keyEquivalent == "w" })
        #expect(windows.items.contains { $0.action == #selector(NSWindow.performMiniaturize) && $0.keyEquivalent == "m" })
    }

    @Test(arguments: [false, true])
    func applicationAndEditingShortcutsRemainAvailable(includesWindowMenu: Bool) throws {
        let app = NSApplication.shared
        let previous = app.windowsMenu
        defer { app.windowsMenu = previous }
        let target = Target()
        let menu = MainMenu.make(target: target, about: #selector(Target.about), settings: #selector(Target.settings), includesWindowMenu: includesWindowMenu)
        let commands = menu.items.compactMap(\.submenu).flatMap(\.items)
        let settings = try #require(commands.first { $0.action == #selector(Target.settings) })

        #expect(settings.target === target)
        #expect(settings.keyEquivalent == ",")
        #expect(commands.contains { $0.action == #selector(Target.about) && $0.target === target })
        #expect(commands.contains { $0.action == #selector(NSApplication.terminate) && $0.keyEquivalent == "q" })
        #expect(commands.contains { $0.action == #selector(NSText.copy(_:)) && $0.keyEquivalent == "c" })
        #expect(commands.contains { $0.action == #selector(NSText.paste(_:)) && $0.keyEquivalent == "v" })
        #expect(commands.contains { $0.action == #selector(NSText.selectAll(_:)) && $0.keyEquivalent == "a" })
    }
}
