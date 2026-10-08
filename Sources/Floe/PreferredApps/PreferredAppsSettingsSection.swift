//
//  PreferredAppsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The app each role stands for: where folders, files and web links are opened, where a note goes, and what keeps the clipboard history.
struct PreferredAppsSettingsSection: View {
    @ObservedObject var settings: AppSettings
    var installed = AppLookup.system

    var body: some View {
        ThawSection("Preferred Apps") {
            PreferredAppPicker(role: .terminal, choice: $settings.terminalApp, installed: installed)
            PreferredAppPicker(role: .editor, choice: $settings.editorApp, installed: installed)
            PreferredAppPicker(role: .browser, choice: $settings.browserApp, installed: installed)
            NotesAppPicker(settings: settings)
            ClipboardAppPicker(settings: settings, installed: installed)
        }
    }
}

/// Which app a note typed into the search goes to, and the link for an app Floe has no name for.
struct NotesAppPicker: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Picker(selection: $settings.notesApp) {
            ForEach(NotesApp.allCases) { app in
                Label {
                    Text(app.title)
                } icon: {
                    Image(nsImage: NotesAppPicker.icon(for: app))
                }
                .tag(app)
            }
        } label: {
            Text(AppRole.notes.title)
            Text(AppRole.notes.detail)
        }
        if settings.notesApp == .custom {
            TextField(text: $settings.notesURLTemplate, prompt: Text(verbatim: "bear://x-callback-url/create?text={text}")) {
                Text("URL")
                Text("The link that makes a note, with {text} where the text goes.")
            }
        }
        if settings.notesApp == .folder {
            LabeledContent {
                Menu("Choose…") {
                    ForEach(KnownNoteFolders.all()) { folder in
                        Button {
                            settings.notesFolder = folder.path
                        } label: {
                            Label {
                                Text(folder.title)
                            } icon: {
                                Image(nsImage: NotesAppPicker.icon(forFile: folder.path))
                            }
                        }
                    }
                    Divider()
                    Button("Another Folder…") { chooseFolder() }
                }
                .fixedSize()
            } label: {
                Text(settings.notesFolder.isEmpty ? String(localized: "No folder chosen", bundle: .floe) : (settings.notesFolder as NSString).abbreviatingWithTildeInPath)
                Text("“note” and some text makes a Markdown file here. “append” adds a line to the day’s note. Obsidian, Octarine and other apps that keep notes as files show them as their own.")
            }
        }
    }
}

extension NotesAppPicker {
    /// The picture beside a choice, as the other pickers have one: the app's own icon when it is installed,
    /// and a symbol for the two choices that are no app.
    static func icon(for app: NotesApp) -> NSImage {
        if let bundleID = app.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return icon(forFile: url.path)
        }
        let image = NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func icon(forFile path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose", bundle: .floe)
        if panel.runModal() == .OK, let url = panel.url {
            settings.notesFolder = url.path
        }
    }
}

/// One role's picker: its default, the known apps on this Mac, and Choose for any other.
struct PreferredAppPicker: View {
    /// Stands for the Choose row, which opens a panel instead of being a choice.
    private static let chooseID = "choose"

    let role: AppRole
    @Binding var choice: AppChoice?
    let installed: AppLookup

    private var options: [AppOption] {
        PreferredApps.options(for: role, choice: choice, installed: installed)
    }

    private var selection: Binding<String> {
        Binding(
            get: { choice?.key ?? AppOption.defaultID },
            set: { id in
                if id == Self.chooseID {
                    // The menu has to close before the panel can open.
                    DispatchQueue.main.async(execute: chooseApp)
                } else {
                    choice = options.first { $0.id == id }?.choice
                }
            }
        )
    }

    var body: some View {
        Picker(selection: selection) {
            ForEach(options) { option in
                Label {
                    Text(option.title)
                } icon: {
                    if let icon = Self.icon(for: option) {
                        Image(nsImage: icon)
                    }
                }
                .tag(option.id)
            }
            Divider()
            Text("Choose…").tag(Self.chooseID)
        } label: {
            Text(role.title)
            Text(role.detail)
        }
    }

    private func chooseApp() {
        guard let path = ModalGuard.chooseApp() else { return }
        choice = PreferredApps.choice(forAppAt: URL(fileURLWithPath: path), installed: installed)
    }

    static func icon(for option: AppOption) -> NSImage? {
        guard let url = option.url else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
