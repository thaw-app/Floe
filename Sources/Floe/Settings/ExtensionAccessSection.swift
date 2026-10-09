//
//  ExtensionAccessSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// On an extension's page: what it has been seen to reach, and that this is a record and not a limit.
struct ExtensionAccessSection: View {
    let extensionName: String
    /// Whether the record is kept, as its switch in Privacy has it.
    var records = true
    var store = ExtensionAccessStore.shared
    @State private var access = ExtensionAccess()

    var body: some View {
        ThawSection("What It Has Reached") {
            if !records {
                Text("The record is switched off. Settings › Privacy turns it on.")
                    .foregroundStyle(.secondary)
            } else if access.isEmpty {
                Text("Nothing has been recorded for this extension yet.")
                    .foregroundStyle(.secondary)
            } else {
                row("Contacted", access.hosts)
                row("Read from", access.reads)
                row("Changed", access.writes)
                row("Started", access.programs)
                LabeledContent {
                    Button("Forget") {
                        store.forget(extensionName)
                        access = ExtensionAccess()
                    }
                } label: {
                    Text(ExtensionAccessSection.since(access.since))
                }
            }
            Text("Floe sees only part of what an extension does, files least of all. Extensions run with everything your account may do.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { access = store.access(of: extensionName) }
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ values: [String]) -> some View {
        if !values.isEmpty {
            LabeledContent(title) {
                Text(verbatim: values.joined(separator: "\n"))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    /// The line beside Forget: since when the record runs.
    static nonisolated func since(_ date: Date?) -> String {
        guard let date else { return String(localized: "Recorded", bundle: .floe, comment: "Beside a button that clears a record.") }
        return String(localized: "Recorded since \(date.formatted(date: .abbreviated, time: .omitted))", bundle: .floe, comment: "The placeholder is a date.")
    }
}
