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
                // A fixed width: the pages' names fit it, and a wider sidebar only narrows the page.
                .navigationSplitViewColumnWidth(SettingsSidebarPaneList.listWidth)
        } detail: {
            detail
                // Fill the detail column so the Form's scrollbar sits on the
                // window's trailing edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Content fades under the titlebar instead of stopping at a hard band.
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .settingsSearchField(search, selection: selection)
        .updateConsentSheet(stores.updates)
        // Glass buttons are capsules, as in macOS's own glass windows.
        .buttonBorderShape(.capsule)
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
            Form {
                AISettingsSection(settings: settings)
            }
            .formStyle(.grouped)
        case .sync:
            SyncSettingsView(catalog: catalog, settings: settings, sync: stores.sync)
        case .quicklinks:
            QuicklinksSettingsPage(store: stores.quicklinks)
        case .fallbacks:
            FallbacksSettingsPage(catalog: catalog, settings: settings, quicklinks: stores.quicklinks)
        case .snippets:
            SnippetsSettingsPage(store: stores.snippets)
        case .extensionStore:
            ExtensionStoreSettingsPage(store: stores.extensions, settings: settings)
        case .appearance:
            AppearanceSettingsPane(settings: settings, follower: stores.appearance)
        case .privacy:
            PrivacySettingsPane(settings: settings, stores: stores)
        case .about:
            FloeAboutPane(updatesManager: stores.updates)
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
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    let updates: UpdatesManager
    let showWelcome: () -> Void

    var body: some View {
        Form {
            ThawSection(.floe("Floe")) {
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
                ThawPicker(selection: $settings.popToRootDelay) {
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
