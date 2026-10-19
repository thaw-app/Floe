//
//  SyncSettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// The Sync page: settings kept the same on your Macs through iCloud, or carried in a file.
struct SyncSettingsView: View {
    let catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    let sync: SettingsSyncStatus

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
        }
        .formStyle(.grouped)
    }
}

extension SearchIndex {
    /// The Sync page's controls, for the settings search.
    static let syncEntries: [SearchEntry] = [
        .on(
            .sync,
            "syncsWithICloud",
            String(localized: "Sync settings with iCloud", bundle: .floe),
            description: String(localized: "Aliases, hotkeys, favorites, appearance, snippets and quicklinks are the same on your Macs. Passwords stay out.", bundle: .floe),
            section: String(localized: "iCloud", bundle: .floe),
            keywords: String(
                localized: "sync, icloud, cloud, macs, devices, backup, share, remove",
                bundle: .floe,
                comment: "Words that find the Sync settings with iCloud setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .on(
            .sync,
            "syncsExtensionSettings",
            String(localized: "Include extension settings", bundle: .floe),
            description: String(localized: "Preferences of your extensions sync too, except passwords, files, folders and chosen apps.", bundle: .floe),
            section: String(localized: "iCloud", bundle: .floe),
            keywords: String(
                localized: "sync, icloud, extensions, extension preferences, extension settings, macs",
                bundle: .floe,
                comment: "Words that find the Include extension settings setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .on(
            .sync,
            "syncsPasswords",
            String(localized: "Sync passwords with iCloud Keychain", bundle: .floe),
            description: String(localized: "Extension passwords and API keys are kept in iCloud Keychain, which has its own switch in System Settings.", bundle: .floe),
            section: String(localized: "iCloud", bundle: .floe),
            keywords: String(
                localized: "passwords, keychain, icloud keychain, api key, secrets, tokens, sync, remove",
                bundle: .floe,
                comment: "Words that find the Sync passwords with iCloud Keychain setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .on(
            .sync,
            "transferSettings",
            String(localized: "Export or import settings", bundle: .floe),
            description: String(localized: "Moves aliases, hotkeys, favorites, appearance and extension preferences to another Mac.", bundle: .floe),
            section: String(localized: "Your Settings", bundle: .floe),
            keywords: String(
                localized: "export, import, backup, transfer, move, file, restore",
                bundle: .floe,
                comment: "Words that find the Export or import settings setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]
}
