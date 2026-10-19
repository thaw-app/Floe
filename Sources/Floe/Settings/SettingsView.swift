//
//  SettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import SwiftUI
import ThawUI

struct SettingsView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection
    @State private var search: SearchModel
    private let stores: SettingsStores

    /// The search is passed in only by the benchmark, which types into it.
    init(catalog: CatalogStore, stores: SettingsStores, selection: SettingsSelection, search: SearchModel? = nil) {
        self.catalog = catalog
        self.stores = stores
        settings = stores.settings
        self.selection = selection
        _search = State(initialValue: search ?? SearchModel())
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebarPaneList(catalog: catalog, settings: settings, selection: selection)
                .navigationSplitViewColumnWidth(min: SettingsSidebarPaneList.listWidth, ideal: SettingsSidebarPaneList.listWidth, max: 250)
        } detail: {
            detail
                // The system toolbar is the pane header: it names the pane and
                // stays put while the form scrolls under it.
                // Named here from the selection, not by each pane: a pane's own title only arrived once the pane was built.
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                // Fill the detail column so the Form's scrollbar sits on the
                // window's trailing edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Content fades under the glass toolbar instead of stopping at a hard band.
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .settingsSearchField(search)
        .updateConsentSheet(stores.updates)
    }

    @ViewBuilder
    private var detail: some View {
        if search.isSearching {
            // Results take over the detail column until one is chosen or the query is cleared.
            SettingsSearchResults(selection: selection) { SearchIndex.entries(commands: catalog.allCommands) }
        } else {
            pane
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch selection.page {
        case .general:
            GeneralSettingsView(settings: settings, updates: stores.updates, showWelcome: stores.showWelcome)
        case .commands:
            CommandsSettingsView(catalog: catalog, settings: settings)
        case .applications:
            ApplicationSettingsView(catalog: catalog, settings: settings)
        case .ai:
            Form { AISettingsSection(settings: settings) }
                .formStyle(.grouped)
        case .sync:
            SyncSettingsView(catalog: catalog, settings: settings, sync: stores.sync)
        case .quicklinks:
            QuicklinksSettingsPage(store: stores.quicklinks)
        case .snippets:
            SnippetsSettingsPage(store: stores.snippets)
        case .extensionStore:
            ExtensionStoreSettingsPage(store: stores.extensions, settings: settings)
        case .appearance:
            AppearanceSettingsPane(settings: settings, follower: stores.appearance)
        case .privacy:
            PrivacySettingsPane(settings: settings, stores: stores)
        case .about:
            AboutSettingsPane(updatesManager: stores.updates, settings: settings)
        case let .extensionPage(name):
            ExtensionSettingsView(
                catalog: catalog,
                settings: settings,
                commands: catalog.allCommands.filter { $0.extensionName == name },
                extensions: stores.extensions,
                access: stores.extensionAccess,
                onRemoved: { selection.page = .extensionStore }
            )
            .id(name)
        }
    }

    /// The pane's name in the toolbar, the one its sidebar row has. Search results name themselves.
    private var title: String {
        guard !search.isSearching else { return String(localized: "Search", bundle: .floe) }
        return switch selection.page {
        case .general: SearchPaneLabel.general.title
        case .commands: SearchPaneLabel.commands.title
        case .applications: SearchPaneLabel.applications.title
        case .ai: SearchPaneLabel.ai.title
        case .sync: SearchPaneLabel.sync.title
        case .quicklinks: SearchPaneLabel.quicklinks.title
        case .snippets: SearchPaneLabel.snippets.title
        case .extensionStore: SearchPaneLabel.extensionStore.title
        case .appearance: SearchPaneLabel.appearance.title
        case .privacy: SearchPaneLabel.privacy.title
        case .about: SearchPaneLabel.about.title
        case let .extensionPage(name): catalog.allCommands.first { $0.extensionName == name }?.extensionTitle ?? name
        }
    }

    /// What the pane holds, under its name in the toolbar; for an extension, where it comes from.
    private var subtitle: String {
        guard !search.isSearching else { return "" }
        switch selection.page {
        case .general: return String(localized: "Hotkey, startup, updates and the welcome tour", bundle: .floe)
        case .commands: return String(localized: "Built-in, shell, script and menu bar commands", bundle: .floe)
        case .applications: return String(localized: "Preferred apps, and aliases and hotkeys for apps", bundle: .floe)
        case .ai: return String(localized: "What answers Ask AI and extensions", bundle: .floe)
        case .sync: return String(localized: "iCloud sync and settings files", bundle: .floe)
        case .quicklinks: return String(localized: "Keywords and fallbacks for web search", bundle: .floe)
        case .snippets: return String(localized: "Text you paste or type by keyword", bundle: .floe)
        case .extensionStore: return String(localized: "Install extensions from the Raycast store", bundle: .floe)
        case .appearance: return String(localized: "Tint, border and shadow for the launcher", bundle: .floe)
        case .privacy: return String(localized: "Permissions and what Floe contacts", bundle: .floe)
        case .about: return String(localized: "Version, updates and credits", bundle: .floe)
        case let .extensionPage(name):
            guard let command = catalog.allCommands.first(where: { $0.extensionName == name }) else { return "" }
            let count = catalog.allCommands.filter { $0.extensionName == name }.count
            // The catalog holds the singular of both as a plural variation.
            return command.source == .raycast
                ? String(localized: "From Raycast · \(count) commands", bundle: .floe, comment: "The placeholder is how many commands an extension has.")
                : String(localized: "\(count) commands", bundle: .floe, comment: "The placeholder is how many commands an extension has.")
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    let updates: UpdatesManager
    let showWelcome: () -> Void

    var body: some View {
        Form {
            ThawSection("Floe") {
                HotkeyRecorder(
                    keyCombination: $settings.toggleHotkey,
                    onRecordingChange: { settings.isRecordingHotkey = $0 },
                    label: {
                        Text("Open Floe")
                    }
                )
                LaunchAtLoginToggle(settings: settings)
                Toggle("Show in Dock", isOn: $settings.showInDock)
                AutomaticUpdateCheckToggle(updatesManager: updates)
                Picker(selection: $settings.popToRootDelay) {
                    Text("Immediately").tag(0)
                    Text("After 30 seconds").tag(30)
                    Text("After 90 seconds").tag(90)
                    Text("After 5 minutes").tag(300)
                } label: {
                    Text("Return to root search")
                    Text("How long a closed launcher keeps the command you had open.")
                }
            }
            WelcomeSettingsSection(showWelcome: showWelcome)
        }
        .formStyle(.grouped)
    }
}
