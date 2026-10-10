//
//  SyncSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// General's section for settings sync: the switch, how it is doing, and the way to delete iCloud's copy.
struct SyncSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var sync: SettingsSyncStatus = .shared

    private var isUnavailable: Bool {
        sync.status.state == .notSigned
    }

    var body: some View {
        ThawSection("iCloud") {
            Toggle(isOn: $settings.syncsWithICloud) {
                Text("Sync settings with iCloud")
                Text("Aliases, hotkeys, favorites, appearance, snippets and quicklinks are the same on your Macs. Passwords stay out.")
            }
            .disabled(isUnavailable)
            Toggle(isOn: $settings.syncsExtensionSettings) {
                Text("Include extension settings")
                Text("Preferences of your extensions sync too. Passwords, files, folders and chosen apps stay on this Mac.")
            }
            .disabled(isUnavailable || !settings.syncsWithICloud)
            LabeledContent("Status") {
                Text(SettingsSyncText.line(for: sync.status)).foregroundStyle(.secondary)
            }
            LabeledContent {
                Button("Remove Settings from iCloud…") { removeFromCloud() }
                    .disabled(isUnavailable || sync.status.state == .noAccount)
            } label: {
                Text("iCloud copy")
                Text("Deletes the copy in iCloud and switches sync off on every Mac. Each Mac keeps its own settings.")
            }
        }
    }

    private func removeFromCloud() {
        let detail = String(localized: "Sync is switched off on every Mac that uses it. The settings on each Mac stay as they are.", bundle: .floe)
        let button = String(localized: "Remove from iCloud", bundle: .floe)
        guard Confirm.destructive(String(localized: "Remove Floe's settings from iCloud?", bundle: .floe), detail: detail, button: button) else { return }
        settings.syncsWithICloud = false
        ProcessLink.current?.send(.removeSyncedSettings)
    }
}
