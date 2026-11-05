//
//  SettingsTheme.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// How Floe draws Settings and the welcome window. Match System follows macOS between light and dark; Black is
/// the dark look on pure black, for OLED displays. The launcher keeps following macOS and its own appearance settings.
enum SettingsTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case black

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system: String(localized: "Match System", bundle: .floe, comment: "A theme for the Settings window: it follows macOS between light and dark.")
        case .light: String(localized: "Light", bundle: .floe, comment: "A theme for the Settings window.")
        case .dark: String(localized: "Dark", bundle: .floe, comment: "A theme for the Settings window.")
        case .black: String(localized: "Black", bundle: .floe, comment: "A theme for the Settings window: dark on pure black.")
        }
    }

    /// Black draws dark controls on its black background.
    var windowAppearance: SettingsWindowAppearance {
        switch self {
        case .system: .system
        case .light: .light
        case .dark, .black: .dark
        }
    }

    var windowBackground: SettingsWindowBackground {
        self == .black ? .black : .system
    }

    /// A grouped form fills itself, which would hide Black's background behind it.
    var formBackground: Visibility {
        self == .black ? .hidden : .automatic
    }
}

extension View {
    /// Holds the hosting window to the theme chosen in Settings, and to each new choice, without drawing a background.
    func heldToSettingsTheme(_ settings: AppSettings) -> some View {
        modifier(HeldToSettingsTheme(settings: settings))
    }
}

private struct HeldToSettingsTheme: ViewModifier {
    @ObservedObject var settings: AppSettings

    func body(content: Content) -> some View {
        content.settingsWindowAppearance(settings.settingsTheme.windowAppearance)
    }
}
