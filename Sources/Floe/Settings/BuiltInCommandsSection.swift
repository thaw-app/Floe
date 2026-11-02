//
//  BuiltInCommandsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Floe's own commands with their aliases and hotkeys, then the options a few of them take.
struct BuiltInCommandsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ThawSection("Built-in Commands") {
            ForEach(LauncherModel.hotkeyViews, id: \.id) { item in
                row(for: item)
            }
            DisclosureGroup("System Commands") {
                ForEach(SystemCommand.allCases) { command in
                    row(for: .system(command))
                }
            }
            ThawPicker("Emoji skin tone", selection: $settings.emojiSkinTone) {
                ForEach(EmojiSkinTone.allCases) { tone in
                    Text(verbatim: tone.applied(to: "\u{1F44B}") + " " + tone.label).tag(tone)
                }
            }
            TextField(text: $settings.focusShortcut, prompt: Text("None")) {
                Text("Shortcut for Focus")
                Text("A Shortcut of yours that sets Focus. It receives the number of minutes, or the word off or toggle.")
            }
            TextField(text: Binding(get: { settings.definitionKeyword }, set: { settings.definitionKeyword = $0.filter { !$0.isWhitespace } }), prompt: Text(verbatim: WordDefinition.keyword)) {
                Text("Dictionary keyword")
                if WordDefinition.isTaken(settings.definitionKeyword) {
                    Text("“\(settings.definitionKeyword)” is already a keyword in the search, so define keeps working.")
                } else {
                    Text("Type this word, then the word you want to look up.")
                }
            }
            ThawSupportNotice()
        }
    }

    @ViewBuilder
    private func row(for item: RootItem) -> some View {
        if let key = item.settingsKey {
            HStack(spacing: ThawSpacing.compact) {
                Text(item.title)
                    .lineLimit(1)
                Spacer()
                TextField(
                    "Alias",
                    text: Binding(get: { settings.aliases[key] ?? "" }, set: { settings.aliases[key] = $0.isEmpty ? nil : $0 }),
                    prompt: Text("Alias")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                HotkeyRecorder(
                    keyCombination: Binding(get: { settings.commandHotkeys[key] }, set: { settings.commandHotkeys[key] = $0 }),
                    onRecordingChange: { settings.isRecordingHotkey = $0 },
                    label: { Text("Hotkey") }
                )
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
