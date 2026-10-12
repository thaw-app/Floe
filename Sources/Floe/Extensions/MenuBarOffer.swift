//
//  MenuBarOffer.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What is asked after an extension with menu-bar commands is installed: whether to add them.
/// Floe starts none on its own, so without the question nothing says they are there.
nonisolated struct MenuBarOffer: Identifiable, Equatable {
    let extensionTitle: String
    /// The commands that can start now, by id and title.
    let ready: [Choice]
    /// The commands that cannot start until the extension's required preferences are set.
    let needingSetup: [Choice]

    struct Choice: Equatable {
        let id: String
        let title: String
    }

    var id: String {
        (ready + needingSetup).map(\.id).joined(separator: ",")
    }

    /// Nil when the extension has no menu-bar command that is not in the menu bar already.
    init?(commands: [ExtensionCommand], inMenuBar: Set<String>, needsSetup: (ExtensionCommand) -> Bool) {
        let offered = commands.filter { $0.mode == "menu-bar" && !inMenuBar.contains($0.id) }
        guard let first = offered.first else { return nil }
        extensionTitle = first.extensionTitle
        ready = offered.filter { !needsSetup($0) }.map { Choice(id: $0.id, title: $0.title) }
        needingSetup = offered.filter(needsSetup).map { Choice(id: $0.id, title: $0.title) }
    }

    var title: String {
        String(localized: "Add \(extensionTitle) to the menu bar?", bundle: .floe, comment: "The title of a question asked after installing an extension. The placeholder is the extension's name.")
    }

    var message: String {
        let later = String(localized: "Set \(extensionTitle)'s preferences on its page before adding \(Self.list(needingSetup)).", bundle: .floe, comment: "The first placeholder is an extension's name, the second the names of one or more of its commands.")
        guard !ready.isEmpty else { return later }
        let now = String(localized: "\(Self.list(ready)) can show in the menu bar. Floe adds a menu bar command only when you ask, and you can change this later under General.", bundle: .floe, comment: "The placeholder is the names of one or more commands. General is the name of a settings page.")
        return needingSetup.isEmpty ? now : now + " " + later
    }

    private static func list(_ choices: [Choice]) -> String {
        choices.map(\.title).formatted(.list(type: .and))
    }
}
