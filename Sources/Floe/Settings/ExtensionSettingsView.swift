//
//  ExtensionSettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// The settings page of one extension: its icon and name, its preferences, and a line for each command.
struct ExtensionSettingsView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    let commands: [ExtensionCommand]
    let extensions: ExtensionStore
    let access: ExtensionAccessStore
    var onRemoved: () -> Void = { /* nowhere to go from a preview */ }
    @State private var confirmingRemoval = false
    @State private var choosingIcon = false
    @State private var iconError: String?

    var body: some View {
        if let first = commands.first {
            Form {
                ExtensionHeader(command: first)
                if !first.extensionPreferences.isEmpty {
                    ThawSection("Preferences") {
                        PreferencesEditor(fields: first.extensionPreferences, extensionName: first.extensionName, command: nil)
                    }
                }
                ThawSection {
                    ExtensionAISourcePicker(settings: settings, extensionName: first.extensionName)
                    ForEach(LentProvider.lent(to: first.extensionName, in: settings.lentSignIns), id: \.self) { provider in
                        LabeledContent {
                            Button("Take Back") { settings.lentSignIns.remove(provider.key(for: first.extensionName)) }
                        } label: {
                            Text("\(provider.name) sign-in", comment: "The placeholder is a service, such as GitHub.")
                            Text("This extension uses the sign-in of the \(provider.toolName) on this Mac.", comment: "The placeholder is the name of a command line tool, such as GitHub CLI.")
                        }
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
                ExtensionAccessSection(extensionName: first.extensionName, records: settings.recordsExtensionAccess, store: access)
            }
            .formStyle(.grouped)
            .toolbar { toolbar(for: first) }
            .settingsSearchAnchorScroll()
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
                    extensions.onInstalled()
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
                    extensions.remove(folder: first.extensionDir, named: first.extensionName)
                    onRemoved()
                }
                Button("Cancel", role: .cancel) { /* the alert closes itself */ }
            } message: {
                if first.source == .raycast {
                    Text("Raycast installed this extension, so Raycast loses it too. Its folder goes to the Trash. Its preferences and what it stored in Floe are kept, for when it is installed again.")
                } else {
                    Text("Its folder goes to the Trash. Its preferences and what it stored are kept, for when it is installed again.")
                }
            }
        }
    }
}

extension ExtensionSettingsView {
    private func isEnabled(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledExtensions.contains(name) },
            set: { enabled in
                if enabled {
                    settings.disabledExtensions.remove(name)
                } else {
                    settings.disabledExtensions.insert(name)
                }
            }
        )
    }

    /// The extension's switch and what else is done to it as a whole, where Raycast has them.
    @ToolbarContentBuilder
    private func toolbar(for first: ExtensionCommand) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Choose Icon…") { choosingIcon = true }
                if CustomIcon.path(for: first.extensionName) != nil {
                    Button("Use Its Own Icon") {
                        CustomIcon.remove(for: first.extensionName)
                        extensions.onInstalled()
                    }
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([first.extensionDir]) }
                // A checkout's samples stay: they are files of the repository.
                if ExtensionStore.canRemove(first.extensionDir) {
                    Divider()
                    Button("Remove Extension…", role: .destructive) { confirmingRemoval = true }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            Toggle("Enabled", isOn: isEnabled(first.extensionName))
                .toggleStyle(.switch)
                .help("An extension that is off is left out of the search, and its hotkeys, menu bar items and Shortcuts do not run.")
        }
    }
}

/// The extension's icon, name and what it does, at the top of its page as Raycast shows them.
private struct ExtensionHeader: View {
    let command: ExtensionCommand

    var body: some View {
        // A header with no rows, so the form draws no card behind it.
        Section {
            EmptyView()
        } header: {
            VStack(spacing: ThawSpacing.compact) {
                IconView(value: command.extensionIcon ?? command.icon ?? "icon:Terminal", assetsPath: command.assetsPath, size: 64)
                HStack(spacing: ThawSpacing.compact) {
                    Text(command.extensionTitle)
                        .font(.largeTitle.weight(.bold))
                    if command.source == .raycast {
                        ThawBadge("Raycast")
                    }
                }
                if let description = command.extensionDescription {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
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
                prompt: Text("Add Alias")
            )
            .labelsHidden()
            .textFieldStyle(.plain)
            .frame(width: 80)
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
