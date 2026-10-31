//
//  CommandsSettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Where commands come from and how each is reached: Floe's own, the shell, scripts, the menu bar and extensions.
struct CommandsSettingsView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @State private var tab = CommandsTab.builtIn

    /// Writes a starter script into the Scripts folder and reveals it, so it can be edited.
    static func makeScript(catalog: CatalogStore) {
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

    var body: some View {
        Form {
            SettingsPageHeader()
            SettingsTabs(selection: $tab)
            switch tab {
            case .builtIn: builtInSections
            case .extensions: extensionsSection
            case .scripts: scriptsSection
            case .menuBar: MenuBarCommandsSettingsSection(catalog: catalog, settings: settings)
            }
        }
        .formStyle(.grouped)
    }

    /// Floe's own commands, the shell's, and what was taken out of the search.
    @ViewBuilder private var builtInSections: some View {
        BuiltInCommandsSection(settings: settings)
        ShellCommandsSettingsSection(settings: settings)
        if !settings.hiddenResults.isEmpty {
            ThawSection(.floe("Hidden from Search")) {
                ForEach(settings.hiddenResults.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }, id: \.key) { hidden in
                    LabeledContent(hidden.value) {
                        Button("Show Again") { settings.hiddenResults[hidden.key] = nil }
                            .buttonStyle(.settingsGlass)
                    }
                }
            }
        }
    }

    private var extensionsSection: some View {
        ThawSection(.floe("Extensions")) {
            Toggle(isOn: $settings.includeRaycastExtensions) {
                Text("Include extensions installed in Raycast")
                Text("Reads ~/.config/raycast/extensions. Their Raycast settings don't carry over.")
            }
            LabeledContent("Extensions folder") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.extensions]) }
                    .buttonStyle(.settingsGlass)
            }
            LabeledContent("Runtime") {
                if Paths.isBunBundled {
                    Text("Bun, bundled with the app").foregroundStyle(ThawInk.supporting)
                } else if let bun = Paths.bun {
                    Text(bun).foregroundStyle(ThawInk.supporting).textSelection(.enabled)
                } else {
                    Text("Bun not found. Install it with brew install bun.").foregroundStyle(.red)
                }
            }
        }
    }

    private var scriptsSection: some View {
        ThawSection(.floe("Script Commands")) {
            LabeledContent("Scripts folder") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.scripts]) }
                    .buttonStyle(.settingsGlass)
            }
            LabeledContent("New") {
                Button("New Script") { Self.makeScript(catalog: catalog) }
                    .buttonStyle(.settingsGlass)
            }
            if catalog.allScripts.isEmpty, catalog.scriptFailures.isEmpty {
                Text("No script commands yet. Scripts are executable files with @raycast metadata.").foregroundStyle(ThawInk.supporting)
            }
            ForEach(catalog.allScripts) { script in
                LabeledContent(script.title) {
                    Text(script.mode.rawValue).foregroundStyle(ThawInk.supporting)
                }
            }
            ForEach(catalog.scriptFailures) { failure in
                LabeledContent(failure.file) {
                    Text(failure.error.localizedDescription).foregroundStyle(.red)
                }
            }
        }
    }
}

/// The Commands page's tabs: Floe's own, extensions, script commands, and what runs in the menu bar.
nonisolated enum CommandsTab: SettingsTab {
    case builtIn
    case extensions
    case scripts
    case menuBar

    init?(entry id: String) {
        switch id {
        case "commands.includeRaycastExtensions", "commands.extensionsFolder", "commands.runtime": self = .extensions
        case "commands.scriptsFolder": self = .scripts
        case "commands.menuBarCommands": self = .menuBar
        case _ where id.hasPrefix("commands."): self = .builtIn
        default: return nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .builtIn: .floe("Built-in")
        case .extensions: .floe("Extensions")
        case .scripts: .floe("Scripts")
        case .menuBar: .floe("Menu Bar")
        }
    }

    var systemImage: String {
        switch self {
        case .builtIn: "command"
        case .extensions: "puzzlepiece.extension"
        case .scripts: "terminal"
        case .menuBar: "menubar.rectangle"
        }
    }
}
