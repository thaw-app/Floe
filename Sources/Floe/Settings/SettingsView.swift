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
            GeneralSettingsView(catalog: catalog, settings: settings, updates: stores.updates, sync: stores.sync, showWelcome: stores.showWelcome)
        case .commands:
            CommandsSettingsView(catalog: catalog, settings: settings)
        case .applications:
            ApplicationSettingsView(catalog: catalog, settings: settings)
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
            AboutSettingsPane(updatesManager: stores.updates)
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
        case .general: return String(localized: "Startup, preferred apps, AI and sync", bundle: .floe)
        case .commands: return String(localized: "Built-in, shell, script and menu bar commands", bundle: .floe)
        case .applications: return String(localized: "Aliases and hotkeys for apps", bundle: .floe)
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
    let catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    let updates: UpdatesManager
    let sync: SettingsSyncStatus
    let showWelcome: () -> Void

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Floe Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let archive = try SettingsTransfer.Archive(
                settings: settings.exportedJSON(),
                preferences: PreferenceStore.allStoredValues(),
                secretKeys: PreferenceStore.secretKeys(for: catalog.allCommands)
            )
            try SettingsTransfer.encode(archive).write(to: url, options: .atomic)
        } catch {
            Self.show(error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let archive = try SettingsTransfer.decode(Data(contentsOf: url))
            let detail = String(localized: "Aliases, hotkeys, favorites and appearance are replaced by the file's. Passwords aren't included in exports.", bundle: .floe)
            guard Confirm.destructive(String(localized: "Replace your settings?", bundle: .floe), detail: detail, button: String(localized: "Replace", bundle: .floe, comment: "The button that replaces the settings with the ones in a file.")) else { return }
            try settings.importJSON(archive.settings)
            for (name, values) in archive.preferences {
                PreferenceStore.merge(values, extensionName: name)
            }
            let summary = SettingsTransfer.summary(of: archive) { Keychain.read(account: "\($0)/\($1)") != nil }
            let done = NSAlert()
            done.messageText = String(localized: "Settings imported", bundle: .floe)
            var lines = [
                String(
                    localized: "\(summary.aliases) aliases, \(summary.hotkeys) hotkeys, \(summary.favorites) favorites, preferences for \(summary.extensions) extensions.",
                    bundle: .floe,
                    comment: "What a settings file brought in. Each placeholder is a count."
                ),
            ]
            if !summary.missingSecrets.isEmpty {
                let names = summary.missingSecrets.joined(separator: "\n")
                lines.append(String(localized: "Enter these again:\n\(names)", bundle: .floe, comment: "The placeholder is a list of password fields, one on each line."))
            }
            done.informativeText = lines.joined(separator: "\n\n")
            done.runModal()
        } catch {
            Self.show(error)
        }
    }

    private static func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn't transfer settings", bundle: .floe)
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

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
            PreferredAppsSettingsSection(settings: settings)
            AISettingsSection(settings: settings)
            SyncSettingsSection(settings: settings, sync: sync)
            ThawSection("Your Settings") {
                LabeledContent {
                    HStack {
                        Button("Export…") { exportSettings() }
                        Button("Import…") { importSettings() }
                    }
                } label: {
                    Text("Settings file")
                    Text("Aliases, hotkeys, favorites, appearance and extension preferences. Passwords stay out.")
                }
            }
            WelcomeSettingsSection(showWelcome: showWelcome)
            DiagnosticsSettingsSection(settings: settings)
        }
        .formStyle(.grouped)
    }
}
