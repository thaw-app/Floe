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
            BuiltInCommandsSection(settings: settings)
            ShellCommandsSettingsSection(settings: settings)
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
            MenuBarCommandsSettingsSection(catalog: catalog, settings: settings)
            if !settings.hiddenResults.isEmpty {
                ThawSection("Hidden from Search") {
                    ForEach(settings.hiddenResults.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }, id: \.key) { hidden in
                        LabeledContent(hidden.value) {
                            Button("Show Again") { settings.hiddenResults[hidden.key] = nil }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
