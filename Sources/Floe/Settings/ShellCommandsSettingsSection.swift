//
//  ShellCommandsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// General's section for shell commands: whether they run, the prefix, and what is offered while one is typed.
struct ShellCommandsSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ThawSection(.floe("Shell Commands")) {
            Toggle(isOn: $settings.shell.runs) {
                Text("Run shell commands from the search")
                Text("Type the prefix and a command. Return runs it out of sight and shows its first line of output; Command-Return opens it in your terminal.")
            }
            LabeledContent("Prefix") {
                ThawPillPicker(selection: $settings.shell.prefix, values: CommandPrefix.allCases, title: \.rawValue)
                    .accessibilityLabel(Text("Prefix"))
            }
            .disabled(!settings.shell.runs)
            Toggle(isOn: $settings.shell.suggests) {
                Text("Suggest while typing a command")
                Text("Earlier commands, programs and paths appear under the command, and Tab finishes the selected one. Your shell history is read, not kept.")
            }
            .disabled(!settings.shell.runs)
            Toggle(isOn: $settings.shell.recognizes) {
                Text("Recognize commands without the prefix")
                Text("A search that starts with a program on this Mac and has a flag, a path or a pipe in it gets a Run row under the other results.")
            }
            .disabled(!settings.shell.runs)
        }
    }
}
