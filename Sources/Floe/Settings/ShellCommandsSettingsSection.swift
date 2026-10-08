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
        ThawSection("Shell Commands") {
            Toggle(isOn: $settings.shell.runs) {
                Text("Run shell commands from the search")
                Text("Type the prefix and a command. Return runs it out of sight and shows its first line of output; Command-Return opens it in your terminal.")
            }
            Picker("Prefix", selection: $settings.shell.prefix) {
                ForEach(CommandPrefix.allCases) { prefix in
                    Text(verbatim: prefix.rawValue).tag(prefix)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.shell.runs)
            Toggle(isOn: $settings.shell.suggests) {
                Text("Suggest while typing a command")
                Text("Earlier commands from your shell's history, programs and paths appear under the command. Tab finishes the selected one. The history file is read on this Mac and nothing from it is kept.")
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
