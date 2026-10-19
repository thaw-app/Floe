//
//  DiagnosticsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Settings → About: the switch for the log file, and the way to it.
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

/// The section on the About page, which is no form: a form of its own, sized to the section so the
/// page's scroll view does the scrolling.
struct DiagnosticsSettingsForm: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            DiagnosticsSettingsSection(settings: settings)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SearchIndex {
    /// The log switch on the About page, for the settings search.
    static let aboutEntries: [SearchEntry] = [
        .on(
            .about,
            "diagnosticLogging",
            String(localized: "Detailed logging", bundle: .floe),
            description: String(localized: "Writes a log for troubleshooting to ~/Library/Logs/Floe.", bundle: .floe),
            section: String(localized: "Diagnostics", bundle: .floe, comment: "The heading over the logging settings."),
            keywords: String(
                localized: "log, logs, logging, diagnostics, debug, troubleshoot, slow, report",
                bundle: .floe,
                comment: "Words that find the Detailed logging setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]
}
