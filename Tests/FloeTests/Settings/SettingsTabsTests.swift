//
//  SettingsTabsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

/// A settings search result opens the tab of its page that holds it.
struct SettingsTabsTests {
    @Test func everyCommandsResultHasATab() {
        let entries = SearchIndex.staticEntries.map(\.id).filter { $0.hasPrefix("commands.") }
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { CommandsTab(entry: $0) != nil })
        #expect(CommandsTab(entry: "commands.runtime") == .extensions)
        #expect(CommandsTab(entry: "commands.scriptsFolder") == .scripts)
        #expect(CommandsTab(entry: "commands.menuBarCommands") == .menuBar)
        #expect(CommandsTab(entry: "commands.runsShellCommands") == .builtIn)
        #expect(CommandsTab(entry: "appearance.border") == nil, "a result of another page")
    }

    @Test func everyAppearanceResultHasATab() {
        let entries = SearchIndex.staticEntries.map(\.id).filter { $0.hasPrefix("appearance.") }
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { AppearanceTab(entry: $0) != nil })
        #expect(AppearanceTab(entry: "appearance.tintColor") == .glass)
        #expect(AppearanceTab(entry: "appearance.shadow") == .edges)
        #expect(AppearanceTab(entry: "appearance.searchFieldBeam") == .layout)
        #expect(AppearanceTab(entry: "commands.runtime") == nil, "a result of another page")
    }
}
