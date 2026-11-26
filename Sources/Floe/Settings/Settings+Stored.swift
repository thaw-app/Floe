//
//  Settings+Stored.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import ThawUI

extension AppSettings {
    /// The settings as they are written to the defaults. Every field is optional, so a file from an
    /// earlier version, or one missing a setting, still reads.
    struct Stored: Codable {
        var toggleHotkey: KeyCombination?
        var commandHotkeys: [String: KeyCombination]?
        var aliases: [String: String]?
        var disabledExtensions: Set<String>?
        var disabledCommands: Set<String>?
        var enabledCommands: Set<String>?
        var includeRaycastExtensions: Bool?
        var popToRootDelay: Int?
        var favorites: [String]?
        var fallbacks: [String]?
        var hiddenResults: [String: String]?
        var actionChoices: [String: KindActions]?
        var emojiSkinTone: EmojiSkinTone?
        var menuBarApp: MenuBarApp?
        var rememberMenuBarQuery: Bool?
        var clipboardHistoryEnabled: Bool?
        var diagnosticLogging: Bool?
        var searchSources: Set<String>?
        var indexesFileNames: Bool?
        var menuBarCommands: Set<String>?
        var notesApp: NotesApp?
        var notesURLTemplate: String?
        var notesFolder: String?
        var terminalApp: AppChoice?
        var editorApp: AppChoice?
        var browserApp: AppChoice?
        var clipboardHandler: ClipboardHandler?
        var clipboardApp: AppChoice?
        var clipboardURL: String?
        var menuBarItemNames: [String: String]?
        var showInDock: Bool?
        var showInMenuBar: Bool?
        var settingsTheme: SettingsTheme?
        var hasSeenOnboarding: Bool?
        var launcherTintIsDynamic: Bool?
        var launcherTintLight: LauncherTint?
        var launcherTintDark: LauncherTint?
        var launcherBorder: LauncherBorder?
        var launcherShowsBorder: Bool?
        var launcherShowsShadow: Bool?
        var launcherGlass: LauncherGlass?
        var followsThawAppearance: Bool?
        var launcherLayout: LauncherLayout?
        var searchFieldShape: SearchFieldShape?
        var searchFieldCorners: SearchFieldCorners?
        var searchFieldBeam: SearchFieldBeam?
        var searchFieldBeamFrameRate: Double?
        var separatesSearchField: Bool?
        var launcherScreen: String?
        var aiSource: AISource?
        var aiBaseURL: String?
        var aiModel: String?
        var aiTool: AITool?
        var aiToolModels: [String: String]?
        var aiOnThisMacOnly: Bool?
        var remembersSearches: Bool?
        var keepsReceipts: Bool?
        var recordsExtensionAccess: Bool?
        var lentSignIns: Set<String>?
        var shellEnvironmentExtensions: Set<String>?
        var shell: ShellSettings?
        var fetchesExchangeRates: Bool?
        var focusShortcut: String?
        var definitionKeyword: String?
        var aiSourceByExtension: [String: AISource]?
        var syncsWithICloud: Bool?
        var syncsExtensionSettings: Bool?
    }
}
