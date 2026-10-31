//
//  ErrorView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Shows the command's view, or the error screen once it has failed.
struct SessionContainer: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var session: ExtensionSession

    var body: some View {
        if let failure = session.failure {
            ErrorView(model: model, session: session, failure: failure).modifier(PanelOnePiece())
        } else {
            ExtensionView(model: model, session: session)
        }
    }
}

struct ErrorView: View {
    @ObservedObject var model: LauncherModel
    let session: ExtensionSession
    let failure: SessionFailure

    private var title: String {
        switch failure.kind {
        case .error: String(localized: "\(session.command.title) ran into an error", bundle: .floe, comment: "The placeholder is the name of a command.")
        case .crashed: String(localized: "\(session.command.title) stopped", bundle: .floe, comment: "The placeholder is the name of a command.")
        case .unresponsive: String(localized: "\(session.command.title) isn't responding", bundle: .floe, comment: "The placeholder is the name of a command.")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: session.command.extensionTitle, icon: session.command.icon, assetsPath: session.command.assetsPath)
            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                    Label {
                        Text(title).font(ThawType.heading)
                    } icon: {
                        Image(systemName: failure.kind == .unresponsive ? "hourglass" : "exclamationmark.triangle.fill")
                            .foregroundStyle(failure.kind == .unresponsive ? Color.orange : Color.red)
                    }
                    Text(failure.message).textSelection(.enabled)
                    if !failure.details.isEmpty {
                        Text(failure.details.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(ThawType.sublabel.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(ThawSpacing.row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: ThawRadius.control))
                    }
                    HStack(spacing: ThawSpacing.base) {
                        Button("Copy Details") { model.runner.copyFailure() }
                        Button("Show Extension in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([session.command.extensionDir])
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Footer(
                primary: failure.kind == .unresponsive ? String(localized: "Restart", bundle: .floe, comment: "A verb on a button: start the extension again.") : String(localized: "Try Again", bundle: .floe),
                runPrimary: model.runner.retry
            ) {
                ShortcutHintButton(title: String(localized: "Back", bundle: .floe, comment: "A button that leaves the error and goes back.")) { model.runner.end(session) } hint: {
                    KeyCapView(text: "esc")
                }
                ShortcutHintButton(title: String(localized: "Copy Details", bundle: .floe)) { model.runner.copyFailure() } hint: {
                    KeyCapView(text: "⌘")
                    KeyCapView(text: "⇧")
                    KeyCapView(text: "C")
                }
            }
        }
    }
}
