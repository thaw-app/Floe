//
//  SettingsStringsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing

/// The settings' text after it became translatable: the English reads as it did, and the search finds what it found.
@MainActor
struct SettingsStringsTests {
    private func found(_ query: String) -> [String] {
        let model = SearchModel()
        model.searchText = query
        return model.displayedGroups.flatMap(\.entries).map(\.id)
    }

    private func mirror(_ unmirrored: [ThawAppearance.Layer], followsTint: Bool) -> ThawMirror {
        let look = LauncherLook(
            glass: LauncherGlass(style: .dynamic, color: StoredColor(Color(red: 0.9, green: 0.1, blue: 0.1))),
            tint: LauncherTint(kind: .gradient, opacity: 0.7),
            border: nil,
            hasShadow: false
        )
        return ThawMirror(look: look, followed: followsTint ? [.tint] : [], unmirrored: unmirrored)
    }

    // MARK: The settings search

    @Test func aKeywordListIsOneStringSplitAtItsCommas() {
        #expect("browser, web browser, default app".searchTerms == ["browser", "web browser", "default app"])
        #expect("navegador，red、 enlaces ،web,".searchTerms == ["navegador", "red", "enlaces", "web"], "a translator's own commas separate too")
        #expect("".searchTerms.isEmpty)
    }

    @Test func theKeywordsOfAnEntryAreTheTermsOfItsList() throws {
        let browser = try #require(SearchIndex.staticEntries.first { $0.id == "general.browserApp" })
        #expect(browser.keywords == ["browser", "web browser", "default browser", "web", "links", "web address", "quicklink", "preferred app", "default app"])
        let about = try #require(SearchIndex.staticEntries.first { $0.id == "pane.about" })
        #expect(about.keywords.count == 15)
        #expect(about.keywords.contains("what's new") && about.keywords.contains("report a bug"))
        #expect(AppRole.terminal.keywords == ["terminal", "shell", "command line", "finder selection"])
    }

    @Test func theIdsAreTheOnesTheWindowKnows() {
        #expect(SearchIndex.staticEntries.map(\.id) == [
            "pane.appearance", "pane.privacy", "pane.general", "pane.applications", "pane.quicklinks", "pane.snippets", "pane.extensionStore", "pane.about",
            "appearance.followThaw", "appearance.launcherLayout", "appearance.searchFieldShape", "appearance.separatesSearchField", "appearance.glassEffect",
            "appearance.tintStyle", "appearance.tintColor", "appearance.tintOpacity", "appearance.border", "appearance.shadow",
            "privacy.permissions", "privacy.accessibility", "privacy.network", "privacy.searchSources", "privacy.searchSources.files",
            "privacy.searchSources.tabs", "privacy.searchSources.shortcuts", "privacy.indexesFileNames", "privacy.shellCommands", "privacy.recordsExtensionAccess", "privacy.reminders", "privacy.contacts", "privacy.keepsReceipts", "privacy.remembersSearches", "privacy.fetchesExchangeRates", "privacy.aiOnThisMacOnly",
            "general.toggleHotkey", "general.launchAtLogin", "general.showInDock", "general.popToRootDelay", "general.emojiSkinTone", "general.focusShortcut", "general.runsShellCommands", "general.suggestsShellCommands", "general.recognizesCommands",
            "general.checkForUpdates",
            "general.diagnosticLogging", "general.menuBarSearchHotkey", "general.menuBarSearchAlias", "general.thawSupport", "general.menuBarCommands",
            "general.terminalApp", "general.editorApp", "general.browserApp", "general.notesApp", "general.clipboardApp", "general.clipboardHistory",
            "general.clearClipboardHistory", "general.transferSettings", "general.includeRaycastExtensions", "general.extensionsFolder", "general.runtime",
            "general.scriptsFolder", "general.aiSource", "general.aiTool", "general.aiAddress", "general.aiModel", "general.aiKey",
            "quicklinks.list", "quicklinks.new", "quicklinks.name", "quicklinks.keyword", "quicklinks.url", "quicklinks.symbol", "quicklinks.fallback",
            "quicklinks.fallbacks",
        ])
    }

    @Test(arguments: ["reminders", "Reminders", "remind", "to do"])
    func remindersFindsItsRowInPrivacy(query: String) throws {
        #expect(found(query).first == "privacy.reminders")
        let entry = try #require(SearchIndex.staticEntries.first { $0.id == "privacy.reminders" })
        #expect(entry.title == "Reminders")
        #expect(entry.section == "Reminders and Events")
        #expect(entry.pane == .privacy)
    }

    @Test func anEntryIsFoundByItsTitleByAKeywordAndByItsSection() throws {
        #expect(found("Launch at Login") == ["general.launchAtLogin"])
        #expect(found("autostart") == ["general.launchAtLogin"], "a keyword finds it too")
        // The section's name finds the entries whose own text carries it; the section is shown, not matched.
        let underMenuBarItems = found("Menu Bar Items")
        #expect(underMenuBarItems == ["general.menuBarSearchHotkey", "general.thawSupport"])
        for id in underMenuBarItems {
            #expect(try #require(SearchIndex.staticEntries.first { $0.id == id }).section == "Menu Bar Items")
        }
        #expect(found("tint") == ["appearance.tintStyle", "appearance.tintColor", "appearance.tintOpacity", "pane.appearance"], "the ranking is the one it was")
    }

    @Test func anExtensionsEntriesKeepTheirSectionsAndTerms() {
        let manifest: [String: Any] = [
            "name": "zeta-tools",
            "title": "Zeta Tools",
            "preferences": [["name": "apiToken", "title": "API Token", "type": "password"]],
            "commands": [["name": "convert", "title": "Convert Units", "mode": "view"]],
        ]
        let commands = ExtensionCommand.commands(inManifest: Fixture.manifest(manifest), folder: URL(fileURLWithPath: "/tmp/zeta-tools"), source: .raycast)
        let entries = SearchIndex.extensionEntries(for: commands)
        #expect(entries.map(\.id) == ["extension.zeta-tools", "extension.zeta-tools.preference.apiToken", "command.zeta-tools/convert"])
        #expect(entries.first?.keywords == ["zeta-tools", "extension", "enabled", "enable", "disable", "raycast"])
        #expect(entries.map(\.section) == [nil, "Preferences", "Command"])
    }

    // MARK: Sentences with a value in them

    @Test func theWallpaperNoteIsOneWholeSentencePerCase() {
        let cannotCopy = "the wallpaper, which the launcher cannot copy, so"
        let cases: [([ThawAppearance.Layer], Bool, String)] = [
            ([.tint], true, "Thaw's tint follows \(cannotCopy) it is left out."),
            ([.tint], false, "Thaw's tint follows \(cannotCopy) the launcher keeps its own tint."),
            ([.background], true, "Thaw's background follows \(cannotCopy) it is left out."),
            ([.background], false, "Thaw's background follows \(cannotCopy) the launcher keeps its own tint."),
            ([.tint, .background], true, "Thaw's tint and background follow \(cannotCopy) it is left out."),
            ([.tint, .background], false, "Thaw's tint and background follow \(cannotCopy) the launcher keeps its own tint."),
        ]
        for (layers, followsTint, sentence) in cases {
            #expect(ThawAppearanceNote.lines(status: .following, mirror: mirror(layers, followsTint: followsTint)) == [sentence])
        }
        #expect(ThawAppearanceNote.lines(status: .following, mirror: mirror([], followsTint: true)).isEmpty)
    }

    @Test func theNotesUnderTheThawSwitchReadAsBefore() {
        #expect(ThawAppearanceNote.lines(status: .noAnswer, mirror: nil) == [
            "Thaw has not answered, so the launcher keeps the last look it had. "
                + "A development build of Floe has to be allowed first: run \"\(ThawAction.authorize.title)\" from the search.",
        ])
        #expect(ThawAppearanceNote.lines(status: .notRunning, mirror: nil) == ["Thaw is not running. The launcher keeps the last look it had and asks again when Thaw opens."])
        #expect(ThawSupportNotice.detail(isInstalled: false) == "Install Thaw and its actions appear in the search.")
        #expect(ThawSupportNotice.detail(isInstalled: true).hasPrefix("Thaw's actions are in the search: type “thaw” to see them."))
    }

    @Test func aNameGoesIntoItsSentence() {
        #expect(ClipboardApps.settingsNotice(for: .unavailable(app: "Clippy", message: "")) == "Clipboard history is handled by Clippy. Floe saves no copies.")
        #expect(ClipboardApps.settingsNotice(for: .unavailable(app: nil, message: "")) == "Clipboard history is handled by another app. Floe saves no copies.")
        #expect(AppRole.editor.defaultTitle(appName: "Zed") == "Default for Text Files (Zed)")
        #expect(AppRole.terminal.defaultTitle(appName: nil) == "Terminal")
        #expect(NoteAction.new.title(text: "buy milk") == "New Note “buy milk”")
        #expect(NoteAction.append.title(text: "") == "Append to Current Note")
        #expect(
            PrivacyNetwork.aiLine(source: .tools, baseURL: "", onThisMacOnly: true)
                == "A command line tool is chosen, which sends questions to the service it is signed in to. While the switch below is on, Floe refuses to ask it, so no question is sent."
        )
        #expect(SettingsTransfer.TransferError.newerVersion(9).errorDescription == "This file was exported by a newer version of Floe.")
    }

    @Test func theRolesKeepTheirNamesAndLines() {
        #expect(AppRole.allCases.map(\.title) == ["Terminal", "Editor", "Browser", "Notes", "Clipboard"])
        #expect(AppRole.notes.detail == "Type “note” and then your text in the search to send it there.")
        #expect(NotesApp.allCases.map(\.title) == ["Apple Notes", "Antinote", "Another App", "A Folder of Notes"])
        #expect(LauncherGlassStyle.allCases.map(\.title).sorted() == ["Clear", "Dynamic Glass", "Liquid Glass", "Regular"])
        #expect(UpdateChannel.allCases.map(\.title) == ["Stable", "Beta"])
    }
}
