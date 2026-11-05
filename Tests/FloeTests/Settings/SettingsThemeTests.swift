//
//  SettingsThemeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import SwiftUI
import Testing
import ThawUI

struct SettingsThemeTests {
    @Test(arguments: [
        (SettingsTheme.system, SettingsWindowAppearance.system, false),
        (.light, .light, false),
        (.dark, .dark, false),
        (.black, .dark, true),
    ])
    func eachThemeHoldsTheWindowAndOnlyBlackDrawsBlack(theme: SettingsTheme, appearance: SettingsWindowAppearance, isBlack: Bool) {
        #expect(theme.windowAppearance == appearance)
        #expect(theme.windowBackground == SettingsWindowBackground(isBlack: isBlack))
        // Otherwise each pane's grouped form covers the black.
        #expect(theme.formBackground == (isBlack ? .hidden : .automatic))
    }

    @MainActor @Test func aWindowHeldToTheThemeTakesEachNewChoice() async throws {
        let suite = "SettingsThemeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        settings.settingsTheme = .dark
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSHostingView(rootView: Color.clear.heldToSettingsTheme(settings))
        // The window is found and held a turn after the view joins it.
        func appearance(becomes name: NSAppearance.Name?) async -> Bool {
            for _ in 0 ..< 100 where window.appearance?.name != name {
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(10))
            }
            return window.appearance?.name == name
        }
        #expect(await appearance(becomes: .darkAqua))
        settings.settingsTheme = .light
        #expect(await appearance(becomes: .aqua))
        settings.settingsTheme = .black
        #expect(await appearance(becomes: .darkAqua), "Black is dark here, without Settings' background")
        settings.settingsTheme = .system
        #expect(await appearance(becomes: nil), "Match System lets the window follow macOS")
    }

    @MainActor @Test func untilAThemeIsChosenSettingsFollowsMacOS() throws {
        let suite = "SettingsThemeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).settingsTheme == .system)
    }

    @Test func eachThemeHasItsOwnNameAndStoredValue() {
        #expect(SettingsTheme.allCases.map(\.rawValue) == ["system", "light", "dark", "black"])
        #expect(Set(SettingsTheme.allCases.map(\.title)).count == 4)
    }

    @MainActor @Test func aThemeFromANewerFloeIsReadAsNoChoice() throws {
        let suite = "SettingsThemeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"settingsTheme":"sepia","showInDock":true}"#.utf8), forKey: "settings")
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.showInDock, "the rest of the settings still load")
        #expect(settings.settingsTheme == .system)
    }
}
