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
    var vault: SecretVault = Keychain.vault
    @State private var passwords = SecretSyncStatus()

    private var isUnavailable: Bool {
        sync.status.state == .notSigned
    }

    /// Off is always allowed, so a Mac whose settings sync went off can still take its passwords back.
    private var canSwitchPasswords: Bool {
        passwords.isOn || (passwords.isAvailable && !isUnavailable && settings.syncsWithICloud)
    }

    private var syncsPasswords: Binding<Bool> {
        Binding(
            get: { passwords.isOn },
            set: { isOn in
                if isOn {
                    vault.turnOn()
                } else {
                    vault.turnOff()
                }
                passwordsChanged()
            }
        )
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
                Text("Preferences of your extensions sync too, except passwords, files, folders and chosen apps.")
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
            Toggle(isOn: syncsPasswords) {
                Text("Sync passwords with iCloud Keychain")
                Text("Extension passwords and API keys are kept in iCloud Keychain, which has its own switch in System Settings.")
            }
            .disabled(!canSwitchPasswords)
            LabeledContent("Passwords") {
                Text(SettingsSyncText.passwordLine(for: passwords)).foregroundStyle(.secondary)
            }
            LabeledContent {
                Button("Remove Passwords from iCloud Keychain…") { removePasswords() }
                    .disabled(!passwords.isAvailable)
            } label: {
                Text("iCloud Keychain copy")
                Text("Switching the sync off leaves the passwords in iCloud Keychain. This deletes them there, on every device.")
            }
        }
        .onAppear { passwords = vault.status }
    }

    private func passwordsChanged() {
        passwords = vault.status
        // The launcher reads the same switch from the defaults, and reads them again when it hears this.
        ProcessLink.current?.send(.settingsChanged)
    }

    private func removePasswords() {
        let detail = String(localized: "This Mac keeps its own copies. Your other devices lose these passwords unless password sync is switched off there first.", bundle: .floe)
        let button = String(localized: "Remove Everywhere", bundle: .floe)
        guard Confirm.destructive(String(localized: "Remove Floe's passwords from iCloud Keychain?", bundle: .floe), detail: detail, button: button) else { return }
        vault.removeEverywhere()
        passwordsChanged()
    }

    private func removeFromCloud() {
        let detail = String(localized: "Sync is switched off on every Mac that uses it. The settings on each Mac stay as they are.", bundle: .floe)
        let button = String(localized: "Remove from iCloud", bundle: .floe)
        guard Confirm.destructive(String(localized: "Remove Floe's settings from iCloud?", bundle: .floe), detail: detail, button: button) else { return }
        settings.syncsWithICloud = false
        ProcessLink.current?.send(.removeSyncedSettings)
    }
}
