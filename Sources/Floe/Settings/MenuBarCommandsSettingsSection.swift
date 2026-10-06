//
//  MenuBarCommandsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The menu-bar commands of the enabled extensions, each with the switch that gives it a status item.
/// Left out when no extension has one.
struct MenuBarCommandsSettingsSection: View {
    @ObservedObject var catalog: SettingsCatalog
    @ObservedObject var settings: AppSettings

    private var commands: [ExtensionCommand] {
        catalog.allCommands
            .filter { $0.mode == "menu-bar" && settings.isEnabled($0) }
            .sorted { ($0.extensionTitle, $0.title) < ($1.extensionTitle, $1.title) }
    }

    var body: some View {
        let commands = commands
        if !commands.isEmpty {
            ThawSection("Menu Bar Commands") {
                ForEach(commands, id: \.id) { command in
                    let needsSetup = !PreferenceStore.missingRequired(for: command).isEmpty
                    Toggle(isOn: binding(for: command)) {
                        Text(command.title)
                        // A command that cannot start yet says where to finish setting it up.
                        Text(
                            needsSetup
                                ? String(localized: "Set \(command.extensionTitle)'s preferences on its page first.", bundle: .floe, comment: "The placeholder is the name of an extension.")
                                : command.extensionTitle
                        )
                    }
                    .disabled(needsSetup && !settings.menuBarCommands.contains(command.id))
                }
            }
        }
    }

    private func binding(for command: ExtensionCommand) -> Binding<Bool> {
        Binding(
            get: { settings.menuBarCommands.contains(command.id) },
            set: { isOn in
                if isOn {
                    settings.menuBarCommands.insert(command.id)
                } else {
                    settings.menuBarCommands.remove(command.id)
                }
            }
        )
    }
}
