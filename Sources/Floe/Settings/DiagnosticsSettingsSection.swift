//
//  DiagnosticsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Settings → General: the switch for the log file, and the way to it.
struct DiagnosticsSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @State private var logFileName: String?

    var body: some View {
        ThawSection("Diagnostics") {
            Toggle(isOn: $settings.diagnosticLogging) {
                Text("Detailed logging")
                Text("Writes launch times, slow searches and failures to ~/Library/Logs/Floe. Never what you type or ask.")
            }
            LabeledContent {
                Button("Show Log Files in Finder") { NSWorkspace.shared.open(DiagnosticLogger.shared.logDirectory) }
            } label: {
                Text("Log files")
                Text(logFileName ?? String(localized: "None yet", bundle: .floe, comment: "Shown in place of a log file's name when no log has been written."))
            }
        }
        .task(id: settings.diagnosticLogging) {
            // The launcher opens the file once it hears of the switch, a moment after it flips here.
            try? await Task.sleep(for: .milliseconds(600))
            logFileName = (DiagnosticLogger.shared.currentLogFile ?? DiagnosticLogger.shared.latestLogFile)?.lastPathComponent
        }
    }
}
