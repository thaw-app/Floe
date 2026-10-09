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
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection
    @State private var search: SearchModel

    /// `search` is passed in only by the benchmark, which types into it.
    init(catalog: SettingsCatalog, settings: AppSettings, selection: SettingsSelection, search: SearchModel? = nil) {
        self.catalog = catalog
        self.settings = settings
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
                .navigationSubtitle(subtitle)
                // Fill the detail column so the Form's scrollbar sits on the
                // window's trailing edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Content fades under the glass toolbar instead of stopping at a hard band.
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .settingsSearchField(search)
        .updateConsentSheet()
    }

    @ViewBuilder
    private var detail: some View {
        if search.isSearching {
            // Results take over the detail column until one is chosen or the query is cleared.
            SettingsSearchResults(selection: selection, commands: catalog.allCommands)
        } else {
            pane
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch selection.page {
        case .general:
            GeneralSettingsView(catalog: catalog, settings: settings)
        case .applications:
            ApplicationSettingsView(catalog: catalog, settings: settings)
        case .quicklinks:
            QuicklinksSettingsPage()
        case .snippets:
            SnippetsSettingsPage()
        case .extensionStore:
            ExtensionStoreSettingsPage()
        case .appearance:
            AppearanceSettingsPane(settings: settings)
        case .privacy:
            PrivacySettingsPane(settings: settings)
        case .about:
            AboutSettingsPane()
        case let .extensionPage(name):
            ExtensionSettingsView(
                catalog: catalog,
                settings: settings,
                commands: catalog.allCommands.filter { $0.extensionName == name },
                onRemoved: { selection.page = .extensionStore }
            )
            .id(name)
        }
    }

    /// What the pane holds, under its name in the toolbar; for an extension, where it comes from.
    private var subtitle: String {
        guard !search.isSearching else { return "" }
        switch selection.page {
        case .general: return String(localized: "Startup, hotkeys and built-in commands", bundle: .floe)
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

// MARK: - SettingsSidebarPaneList

/// Thaw 3's settings sidebar: a standard source list, so selection, keyboard and VoiceOver
/// come from AppKit rather than from hand-drawn rows.
private struct SettingsSidebarPaneList: View {
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    static let listWidth: CGFloat = 210

    /// Width of the icon column, so labels line up whatever each symbol's
    /// own width is.
    private static let iconColumn: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme
    @Environment(SearchModel.self) private var search

    /// The accent, deepened in dark mode so a light one such as yellow keeps
    /// its contrast against the selected label.
    private var accent: Color {
        colorScheme == .dark ? Color.accentColor.mix(with: .black, by: 0.4) : Color.accentColor
    }

    private nonisolated struct Row: Identifiable {
        let page: SettingsPage
        let title: String
        let symbol: String?
        let icon: String?
        let assetsPath: String
        var isDimmed = false
        var id: SettingsPage {
            page
        }
    }

    /// General and Applications first, then each extension, About last, as in Thaw.
    private var rows: [Row] {
        let extensions = catalog.allCommands
            .uniqued(on: \.extensionName)
            .sorted { $0.extensionTitle.localizedCaseInsensitiveCompare($1.extensionTitle) == .orderedAscending }
            .map { command in
                Row(
                    page: .extensionPage(command.extensionName),
                    title: command.extensionTitle,
                    symbol: nil,
                    icon: command.icon ?? "icon:Terminal",
                    assetsPath: command.assetsPath,
                    isDimmed: settings.disabledExtensions.contains(command.extensionName)
                )
            }
        return [
            Row(page: .general, title: SearchPaneLabel.general.title, symbol: "gearshape", icon: nil, assetsPath: ""),
            Row(page: .applications, title: SearchPaneLabel.applications.title, symbol: "square.grid.2x2", icon: nil, assetsPath: ""),
            Row(page: .quicklinks, title: SearchPaneLabel.quicklinks.title, symbol: "link", icon: nil, assetsPath: ""),
            Row(page: .snippets, title: SearchPaneLabel.snippets.title, symbol: "text.quote", icon: nil, assetsPath: ""),
            Row(page: .extensionStore, title: SearchPaneLabel.extensionStore.title, symbol: "bag", icon: nil, assetsPath: ""),
            Row(page: .appearance, title: SearchPaneLabel.appearance.title, symbol: "paintbrush", icon: nil, assetsPath: ""),
            Row(page: .privacy, title: SearchPaneLabel.privacy.title, symbol: "hand.raised", icon: nil, assetsPath: ""),
        ] + extensions + [
            Row(page: .about, title: SearchPaneLabel.about.title, symbol: "cube", icon: nil, assetsPath: ""),
        ]
    }

    var body: some View {
        // No Sections: an outline-backed list crashes AppKit on macOS 27.0 and 27.2
        // (freed row view in sizeLastColumnToFit).
        // No row is selected during a search, so a click on any row, the current pane's included, ends it.
        List(selection: Binding(
            get: { search.isSearching ? nil : selection.page },
            set: {
                if let page = $0 {
                    SettingsSearchNavigation.selectSidebarPane(page, selection: selection, search: search)
                }
            }
        )) {
            ForEach(rows) { row in
                Label {
                    Text(row.title)
                        .font(ThawType.detail.weight(.medium))
                        .foregroundStyle(row.isDimmed ? Color.secondary : Color.primary)
                        .lineLimit(1)
                } icon: {
                    Group {
                        if let symbol = row.symbol {
                            Image(systemName: symbol)
                                .font(ThawType.symbol.weight(.medium))
                                .foregroundStyle(Color.secondary)
                        } else {
                            IconView(value: row.icon, assetsPath: row.assetsPath, size: 16)
                                .opacity(row.isDimmed ? 0.5 : 1)
                        }
                    }
                    .frame(width: Self.iconColumn)
                }
                // Only the selection fill carries the accent. Applied per row,
                // where the sidebar reads it.
                .listItemTint(row.page == selection.page && !search.isSearching ? .preferred(accent) : .monochrome)
                .tag(row.page)
            }
        }
        .listStyle(.sidebar)
        // The selection fill uses the same deepened accent.
        .tint(accent)
        // Medium rows whatever the system's sidebar size: at Large the labels
        // and symbols crowd a settings window this narrow.
        .environment(\.sidebarRowSize, .medium)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, ThawSpacing.base, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings

    /// Writes a starter script into the Scripts folder and reveals it, so it can be edited.
    static func makeScript(catalog: SettingsCatalog) {
        Paths.prepareSupportFolders()
        var index = catalog.allScripts.count + 1
        var file = Paths.scripts.appendingPathComponent("script-\(index).sh")
        while FileManager.default.fileExists(atPath: file.path) {
            index += 1
            file = Paths.scripts.appendingPathComponent("script-\(index).sh")
        }
        try? ScriptRunner.template().write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        catalog.reloadScripts()
        // The launcher lists scripts too, and has its own copy of the list.
        ProcessLink.current?.send(.rescan(.scripts))
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

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
                Toggle("Launch at Login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Toggle("Show in Dock", isOn: $settings.showInDock)
                AutomaticUpdateCheckToggle()
                Picker(selection: $settings.popToRootDelay) {
                    Text("Immediately").tag(0)
                    Text("After 30 seconds").tag(30)
                    Text("After 90 seconds").tag(90)
                    Text("After 5 minutes").tag(300)
                } label: {
                    Text("Return to root search")
                    Text("How long a closed launcher keeps the command you had open.")
                }
                Picker("Emoji skin tone", selection: $settings.emojiSkinTone) {
                    ForEach(EmojiSkinTone.allCases) { tone in
                        Text(verbatim: tone.applied(to: "\u{1F44B}") + " " + tone.label).tag(tone)
                    }
                }
                TextField(text: $settings.focusShortcut, prompt: Text("None")) {
                    Text("Shortcut for Focus")
                    Text("A Shortcut of yours that sets Focus. It receives the number of minutes, or the word off or toggle.")
                }
            }
            ShellCommandsSettingsSection(settings: settings)
            if !settings.hiddenResults.isEmpty {
                ThawSection("Hidden from Search") {
                    ForEach(settings.hiddenResults.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }, id: \.key) { hidden in
                        LabeledContent(hidden.value) {
                            Button("Show Again") { settings.hiddenResults[hidden.key] = nil }
                        }
                    }
                }
            }
            BuiltInHotkeysSection(settings: settings)
            ThawSection("Menu Bar Items") {
                HotkeyRecorder(
                    keyCombination: Binding(
                        get: { settings.commandHotkeys[RootItem.menuBarSearchKey] },
                        set: { settings.commandHotkeys[RootItem.menuBarSearchKey] = $0 }
                    ),
                    onRecordingChange: { settings.isRecordingHotkey = $0 },
                    label: {
                        Text("Search Menu Bar Items")
                        Text("Find an item in the menu bar and open its menu.")
                    }
                )
                TextField(
                    "Alias",
                    text: Binding(
                        get: { settings.aliases[RootItem.menuBarSearchKey] ?? "" },
                        set: { settings.aliases[RootItem.menuBarSearchKey] = $0.isEmpty ? nil : $0 }
                    ),
                    prompt: Text("None")
                )
                ThawSupportNotice()
            }
            MenuBarCommandsSettingsSection(catalog: catalog, settings: settings)
            WelcomeSettingsSection()
            DiagnosticsSettingsSection(settings: settings)
            PreferredAppsSettingsSection(settings: settings)
            ClipboardSettingsSection(settings: settings)
            AISettingsSection(settings: settings)
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
            ThawSection("Extensions") {
                Toggle(isOn: $settings.includeRaycastExtensions) {
                    Text("Include extensions installed in Raycast")
                    Text("Reads ~/.config/raycast/extensions. Their Raycast settings don't carry over.")
                }
                LabeledContent("Extensions folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.extensions]) }
                }
                LabeledContent("Runtime") {
                    if Paths.isBunBundled {
                        Text("Bun, bundled with the app").foregroundStyle(.secondary)
                    } else if let bun = Paths.bun {
                        Text(bun).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Text("Bun not found. Install it with brew install bun.").foregroundStyle(.red)
                    }
                }
            }
            ThawSection("Script Commands") {
                LabeledContent("Scripts folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.scripts]) }
                }
                LabeledContent("New") {
                    Button("New Script") { Self.makeScript(catalog: catalog) }
                }
                if catalog.allScripts.isEmpty, catalog.scriptFailures.isEmpty {
                    Text("No script commands yet. Scripts are executable files with @raycast metadata.").foregroundStyle(.secondary)
                }
                ForEach(catalog.allScripts) { script in
                    LabeledContent(script.title) {
                        Text(script.mode.rawValue).foregroundStyle(.secondary)
                    }
                }
                ForEach(catalog.scriptFailures) { failure in
                    LabeledContent(failure.file) {
                        Text(failure.error.localizedDescription).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

/// Aliases and hotkeys for apps. Rows are plain text so the page stays cheap with hundreds of apps;
/// the editing controls exist only for the selected app.
struct ApplicationSettingsView: View {
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings
    @State private var filter = ""
    @State private var selection: URL?

    var body: some View {
        let apps = catalog.apps.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        VStack(spacing: 0) {
            editor
            Divider()
            // In the pane, not the toolbar: the toolbar's field searches the settings.
            HStack(spacing: ThawSpacing.compact) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("Filter applications", text: $filter)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, ThawSpacing.section)
            .padding(.vertical, ThawSpacing.compact)
            Divider()
            List(apps, id: \.url, selection: $selection) { app in
                let key = Self.key(app)
                HStack(spacing: ThawSpacing.row) {
                    AppIconView(path: app.url.path, size: 18)
                    Text(app.name).lineLimit(1)
                    Spacer()
                    if let alias = settings.aliases[key] {
                        KeyCap(alias)
                    }
                    Text(settings.commandHotkeys[key]?.displayValue ?? "")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .overlay {
                if apps.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
        }
        .navigationTitle("Applications")
    }

    private static func key(_ app: AppEntry) -> String {
        RootItem.app(app).settingsKey ?? app.url.path
    }

    @ViewBuilder
    private var editor: some View {
        if let app = catalog.apps.first(where: { $0.url == selection }) {
            let key = Self.key(app)
            Form {
                ThawSection {
                    HStack(spacing: ThawSpacing.compact) {
                        AppIconView(path: app.url.path, size: 14)
                        Text(app.name)
                    }
                } content: {
                    TextField(
                        "Alias",
                        text: Binding(
                            get: { settings.aliases[key] ?? "" },
                            set: { settings.aliases[key] = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("None")
                    )
                    HotkeyRecorder(
                        keyCombination: Binding(get: { settings.commandHotkeys[key] }, set: { settings.commandHotkeys[key] = $0 }),
                        onRecordingChange: { settings.isRecordingHotkey = $0 },
                        label: {
                            Text("Hotkey")
                            Text("Opens the app, or hides it if it's already in front.")
                        }
                    )
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 170)
            .id(key)
        } else {
            Text("Select an app to give it an alias or a hotkey.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        }
    }
}
