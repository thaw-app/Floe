//
//  SettingsThemeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

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
