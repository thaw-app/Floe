//
//  ApplicationSettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Aliases and hotkeys for apps. A row is plain text so the page stays cheap with hundreds of apps;
/// the editing controls exist only in the row that was clicked.
struct ApplicationSettingsView: View {
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings
    @State private var filter = ""
    @State private var selection: URL?

    var body: some View {
        let apps = catalog.apps.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        Form {
            ThawSection {
                // In the pane, not the toolbar: the toolbar's field searches the settings.
                HStack(spacing: ThawSpacing.compact) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter applications", text: $filter, prompt: Text("Filter applications"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                }
            } footer: {
                Text("Click an app to give it an alias or a hotkey. A hotkey opens the app, or hides it if it's already in front.")
            }
            ThawSection {
                ForEach(apps, id: \.url) { app in
                    ApplicationSettingsRow(settings: settings, app: app, isEdited: selection == app.url)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = app.url }
                }
                if apps.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One app on one line: its alias and hotkey as text, or as the controls that change them.
private struct ApplicationSettingsRow: View {
    @ObservedObject var settings: AppSettings
    let app: AppEntry
    let isEdited: Bool

    var body: some View {
        let key = RootItem.app(app).settingsKey ?? app.url.path
        HStack(spacing: ThawSpacing.compact) {
            AppIconView(path: app.url.path, size: 20)
            Text(app.name)
                .lineLimit(1)
            Spacer()
            if isEdited {
                TextField(
                    "Alias",
                    text: Binding(
                        get: { settings.aliases[key] ?? "" },
                        set: { settings.aliases[key] = $0.isEmpty ? nil : $0 }
                    ),
                    prompt: Text("Alias")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                HotkeyRecorder(
                    keyCombination: Binding(get: { settings.commandHotkeys[key] }, set: { settings.commandHotkeys[key] = $0 }),
                    onRecordingChange: { settings.isRecordingHotkey = $0 },
                    label: {
                        Text("Hotkey")
                    }
                )
                .labelsHidden()
                .fixedSize()
            } else {
                if let alias = settings.aliases[key] {
                    KeyCap(alias)
                }
                if let hotkey = settings.commandHotkeys[key] {
                    Text(hotkey.displayValue)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        // The controls are taller than the text: every row keeps their height, so a click moves nothing.
        .frame(minHeight: 24)
    }
}
