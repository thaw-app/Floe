//
//  RaycastImportFlow.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import AppKit
import Foundation

/// Brings Raycast's quicklinks into Floe: a file, its passphrase if it is a backup, then a summary of what came in.
enum RaycastImportFlow {
    struct Environment {
        /// The chosen file; nil when the user cancelled.
        var chooseFile: () -> URL?
        /// The passphrase, asked `again` after a wrong one; nil when the user cancelled.
        var askPassphrase: (_ again: Bool) -> String?
        /// Reads the file and what is in it; a file that cannot be read is not an export.
        var read: (URL, String?) async -> RaycastExport.Reading
        var apps: QuicklinkImport.Apps
        var tell: (_ title: String, _ detail: String) -> Void
    }

    static func run(into store: QuicklinkStore, environment: Environment) async {
        guard let file = environment.chooseFile() else { return }
        var passphrase: String?
        while true {
            switch await environment.read(file, passphrase) {
            case .needsPassphrase, .wrongPassphrase where passphrase == nil:
                guard let typed = environment.askPassphrase(false) else { return }
                passphrase = typed
            case .wrongPassphrase:
                guard let typed = environment.askPassphrase(true) else { return }
                passphrase = typed
            case .notAnExport:
                environment.tell(
                    String(localized: "This isn't a Raycast export", bundle: .floe),
                    String(localized: "Choose a file from Raycast's Export Quicklinks, or a backup from Export Settings & Data.", bundle: .floe)
                )
                return
            case let .quicklinks(links):
                let plan = QuicklinkImport.plan(links, existing: store.links, apps: environment.apps)
                store.links.append(contentsOf: plan.added)
                environment.tell(title(added: plan.added.count), detail(of: plan))
                return
            }
        }
    }

    private static func title(added: Int) -> String {
        added == 0
            ? String(localized: "No quicklinks imported", bundle: .floe)
            : String(localized: "Imported \(added) quicklinks", bundle: .floe, comment: "The placeholder is a number of quicklinks.")
    }

    private static func detail(of plan: QuicklinkImport.Plan) -> String {
        var lines = plan.withoutApp.map {
            String(localized: "\($0) opens in your default app: its app isn't on this Mac.", bundle: .floe, comment: "The placeholder is the name of a quicklink.")
        }
        if !plan.skipped.isEmpty {
            lines.append(String(localized: "Not imported:", bundle: .floe, comment: "Above a list of quicklinks that were left out of an import."))
            lines += plan.skipped.map { "\($0.name): \(reason($0.reason))" }
        }
        return lines.joined(separator: "\n")
    }

    private static func reason(_ reason: QuicklinkImport.Reason) -> String {
        switch reason {
        case .alreadyThere:
            String(localized: "already in Floe.", bundle: .floe, comment: "Why a quicklink was left out of an import.")
        case .severalArguments:
            String(localized: "Floe fills in one search term, and this link asks for several.", bundle: .floe, comment: "Why a quicklink was left out of an import.")
        case let .placeholder(name):
            String(localized: "Floe can't fill {\(name)}.", bundle: .floe, comment: "Why a quicklink was left out of an import. The placeholder is a Raycast placeholder such as clipboard.")
        case .notALink:
            String(localized: "not a web address or a path.", bundle: .floe, comment: "Why a quicklink was left out of an import.")
        }
    }
}
