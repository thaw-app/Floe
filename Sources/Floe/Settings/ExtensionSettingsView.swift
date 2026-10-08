//
//  ExtensionSettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// The settings page of one extension: its switch and icon, its preferences, and a line for each command.
struct ExtensionSettingsView: View {
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings
    let commands: [ExtensionCommand]
    var onRemoved: () -> Void = { /* nowhere to go from a preview */ }
    @State private var confirmingRemoval = false
    @State private var choosingIcon = false
    @State private var iconError: String?

    var body: some View {
        if let first = commands.first {
            Form {
                ThawSection {
                    Toggle(isOn: Binding(
                        get: { !settings.disabledExtensions.contains(first.extensionName) },
                        set: { enabled in
                            if enabled {
                                settings.disabledExtensions.remove(first.extensionName)
                            } else {
                                settings.disabledExtensions.insert(first.extensionName)
                            }
                        }
                    )) {
                        HStack(spacing: ThawSpacing.compact) {
                            Text("Enabled")
                            if first.source == .raycast {
                                ThawBadge("Raycast")
                            }
                        }
                        if !settings.disabledExtensions.contains(first.extensionName) {
                            Text("Commands on: \(commands.count { settings.isEnabled($0) }) of \(commands.count)", comment: "Both placeholders are numbers: how many of an extension's commands are switched on, and how many it has.")
                        }
                        Text((first.extensionDir.path as NSString).abbreviatingWithTildeInPath)
                    }
                    LabeledContent("Icon") {
                        HStack(spacing: ThawSpacing.compact) {
                            IconView(value: first.icon ?? "icon:Terminal", assetsPath: first.assetsPath, size: 18)
                            Button("Choose Image…") { choosingIcon = true }
                            if CustomIcon.path(for: first.extensionName) != nil {
                                Button("Use Its Own") {
                                    CustomIcon.remove(for: first.extensionName)
                                    ExtensionStore.shared.onInstalled()
                                }
                            }
                        }
                    }
                    ExtensionAISourcePicker(settings: settings, extensionName: first.extensionName)
                    if settings.lentSignIns.contains(LentProvider.github.key(for: first.extensionName)) {
                        LabeledContent {
                            Button("Take Back") { settings.lentSignIns.remove(LentProvider.github.key(for: first.extensionName)) }
                        } label: {
                            Text("GitHub sign-in")
                            Text("This extension uses the sign-in of the GitHub CLI on this Mac.")
                        }
                    }
                }
                if !first.extensionPreferences.isEmpty {
                    ThawSection("Preferences") {
                        PreferencesEditor(fields: first.extensionPreferences, extensionName: first.extensionName, command: nil)
                    }
                }
                ExtensionAccessSection(extensionName: first.extensionName)
                // Only what Floe installed is Floe's to remove: Raycast's own extensions and a checkout's samples stay.
                if first.extensionDir.deletingLastPathComponent().standardizedFileURL == Paths.extensions.standardizedFileURL {
                    ThawSection {
                        Button("Remove Extension…", role: .destructive) { confirmingRemoval = true }
                    }
                }
                ThawSection("Commands") {
                    ForEach(commands) { command in
                        CommandSettingsRow(settings: settings, command: command)
                            // Where a search result for this command scrolls to.
                            .id(command.id)
                        if !command.commandPreferences.isEmpty {
                            DisclosureGroup {
                                PreferencesEditor(fields: command.commandPreferences, extensionName: command.extensionName, command: command)
                            } label: {
                                Text("\(command.title) Preferences", comment: "The placeholder is a command's name.")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .settingsSearchAnchorScroll()
            .navigationTitle(first.extensionTitle)
            // The importer and what it does with a picture follow Thaw's picker for its menu bar icon.
            .fileImporter(isPresented: $choosingIcon, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if scoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    try CustomIcon.set(url, for: first.extensionName)
                    ExtensionStore.shared.onInstalled()
                } catch {
                    iconError = error.localizedDescription
                }
            }
            .alert("That picture could not be used.", isPresented: Binding(get: { iconError != nil }, set: {
                if !$0 {
                    iconError = nil
                }
            })) {
                Button("OK") { iconError = nil }
            } message: {
                Text(iconError ?? "")
            }
            .alert("Remove \u{201C}\(first.extensionTitle)\u{201D}?", isPresented: $confirmingRemoval) {
                Button("Remove", role: .destructive) {
                    ExtensionStore.shared.remove(first.extensionDir.lastPathComponent)
                    onRemoved()
                }
                Button("Cancel", role: .cancel) { /* the alert closes itself */ }
            } message: {
                Text("Its folder goes to the Trash. Its preferences and what it stored are kept, for when it is installed again.")
            }
        }
    }
}

/// One command of an extension on one line: what it is, the alias and hotkey it answers to, and whether it is on.
struct CommandSettingsRow: View {
    @ObservedObject var settings: AppSettings
    let command: ExtensionCommand

    var body: some View {
        HStack(spacing: ThawSpacing.compact) {
            IconView(value: command.icon ?? "icon:Terminal", assetsPath: command.assetsPath, size: 14)
            Text(command.title)
                .lineLimit(1)
            if command.mode == "no-view" {
                ThawBadge("No View")
            }
            Spacer()
            TextField(
                "Alias",
                text: Binding(
                    get: { settings.aliases[command.id] ?? "" },
                    set: { settings.aliases[command.id] = $0.isEmpty ? nil : $0 }
                ),
                prompt: Text("Alias")
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            HotkeyRecorder(
                keyCombination: Binding(get: { settings.commandHotkeys[command.id] }, set: { settings.commandHotkeys[command.id] = $0 }),
                onRecordingChange: { settings.isRecordingHotkey = $0 },
                label: {
                    Text("Hotkey")
                }
            )
            .labelsHidden()
            .fixedSize()
            Toggle("Enabled", isOn: settings.enabledBinding(for: command))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(settings.disabledExtensions.contains(command.extensionName))
                .help("A command that is off is left out of the launcher and is not run by its hotkey, the menu bar or Shortcuts.")
        }
    }
}

/// Edits stored preference values; saved on each change, passwords to the Keychain.
struct PreferencesEditor: View {
    let fields: [FieldSpec]
    let extensionName: String
    let command: ExtensionCommand?
    @State private var values: [String: String] = [:]
    @State private var loaded = false

    var body: some View {
        ForEach(fields) { field in
            FieldEditor(field: field, value: Binding(
                get: { values[field.name] ?? "" },
                set: { values[field.name] = $0 }
            ))
        }
        .onAppear(perform: load)
        .onChange(of: values) { save() }
    }

    private func load() {
        values = Dictionary(uniqueKeysWithValues: fields.map { field in
            let stored = PreferenceStore.value(field, extensionName: extensionName, command: command)
            return (field.name, FieldValues.initialText(for: field, stored: stored))
        })
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        PreferenceStore.save(FieldValues.typed(values, fields: fields), fields: fields, extensionName: extensionName, command: command)
    }
}
