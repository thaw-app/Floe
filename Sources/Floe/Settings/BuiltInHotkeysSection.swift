//
//  BuiltInHotkeysSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Hotkeys for Floe's own views and the system commands. Menu bar search keeps its row in its own section.
struct BuiltInHotkeysSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ThawSection("Hotkeys for Built-in Commands") {
            ForEach(LauncherModel.hotkeyViews.filter { $0.settingsKey != RootItem.menuBarSearchKey }, id: \.id) { item in
                recorder(for: item)
            }
            DisclosureGroup("System Commands") {
                ForEach(SystemCommand.allCases) { command in
                    recorder(for: .system(command))
                }
            }
        }
    }

    @ViewBuilder
    private func recorder(for item: RootItem) -> some View {
        if let key = item.settingsKey {
            HotkeyRecorder(
                keyCombination: Binding(get: { settings.commandHotkeys[key] }, set: { settings.commandHotkeys[key] = $0 }),
                onRecordingChange: { settings.isRecordingHotkey = $0 },
                label: { Text(item.title) }
            )
        }
    }
}
