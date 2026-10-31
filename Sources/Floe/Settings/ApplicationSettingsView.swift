//
//  ApplicationSettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// The apps Floe opens things in, then aliases and hotkeys for each app. A row is plain text so the
/// page stays cheap with hundreds of apps; the editing controls exist only in the row that was clicked.
struct ApplicationSettingsView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @State private var filter = ""
    @State private var selection: URL?

    var body: some View {
        let apps = catalog.apps.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        ScrollViewReader { proxy in
            form(apps)
                // The app the arrows moved to stays in sight.
                .onChange(of: selection) {
                    if let selection {
                        withAnimation { proxy.scrollTo(selection) }
                    }
                }
                // The arrows go from app to app, as in the sidebar. A field being typed in keeps its own.
                .onMoveCommand { direction in
                    switch direction {
                    case .up: move(by: -1, in: apps)
                    case .down: move(by: 1, in: apps)
                    default: break
                    }
                }
        }
    }

    private func move(by offset: Int, in apps: [AppEntry]) {
        if let next = apps.item(stepping: offset, from: { $0.url == selection }) {
            selection = next.url
        }
    }

    private func form(_ apps: [AppEntry]) -> some View {
        Form {
            PreferredAppsSettingsSection(settings: settings)
            ThawSection {
                // In the pane: the sidebar's field searches the settings.
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
                    ApplicationSettingsRow(settings: settings, app: app, isEdited: selection == app.url) { selection = app.url }
                        .id(app.url)
                }
                if apps.isEmpty {
                    NoMatchesState(query: filter)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One app on one line: its alias and hotkey as text, or the controls that change them.
private struct ApplicationSettingsRow: View {
    @ObservedObject var settings: AppSettings
    let app: AppEntry
    let isEdited: Bool
    let edit: () -> Void

    var body: some View {
        let key = RootItem.app(app).settingsKey ?? app.url.path
        Group {
            if isEdited {
                HStack(spacing: ThawSpacing.compact) {
                    name
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
                }
            } else {
                // Not a Button: one for each of hundreds of apps doubled the time the page takes to lay out.
                HStack(spacing: ThawSpacing.compact) {
                    name
                    if let alias = settings.aliases[key] {
                        KeyCap(alias)
                    }
                    if let hotkey = settings.commandHotkeys[key] {
                        Text(hotkey.displayValue)
                            .foregroundStyle(ThawInk.supporting)
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: edit)
                // What a click does, for the keyboard and VoiceOver.
                .focusable()
                .onKeyPress(keys: [.return, .space]) { _ in
                    edit()
                    return .handled
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, edit)
            }
        }
        // The controls are taller than the text: every row keeps their height, so a click moves nothing.
        .frame(minHeight: Self.height)
        // The app being edited has the sidebar's selected fill, a little wider than the row so its edge clears the icon.
        .padding(.horizontal, ThawSpacing.compact)
        .selectedRowBackground(isEdited)
        .padding(.horizontal, -ThawSpacing.compact)
    }

    private static let height: CGFloat = 24

    @ViewBuilder
    private var name: some View {
        AppIconView(path: app.url.path, size: 20)
        Text(app.name)
            .lineLimit(1)
        Spacer()
    }
}
