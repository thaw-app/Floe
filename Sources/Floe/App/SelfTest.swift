//
//  SelfTest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// `Floe --selftest <extension> <command>` runs a command without UI and reports the first list it renders.
func runSelfTest(extensionName: String, commandName: String) -> Never {
    guard let command = ExtensionCommand.scan().first(where: { $0.extensionName == extensionName && $0.name == commandName }) else {
        print("SELFTEST FAIL: no command \(extensionName)/\(commandName)")
        exit(1)
    }
    let missing = PreferenceStore.missingRequired(for: command).map(\.name)
    if !missing.isEmpty {
        print("SELFTEST missing required preferences: \(missing)")
    }
    let session = ExtensionSession(command: command)
    session.onMessage = { print("SELFTEST message:", $0["type"] ?? "?") }
    let observer = session.objectWillChange.sink { _ in
        DispatchQueue.main.async {
            if let failure = session.failure {
                print("SELFTEST FAILURE: kind=\(failure.kind) message=\(failure.message.debugDescription) logLines=\(failure.details.split(separator: "\n").count)")
                session.forceStop()
                exit(0)
            }
            if let toast = session.toast, toast.style == "failure" {
                print("SELFTEST TOAST: \(toast.title): \(toast.message ?? "")")
            }
            let rows = session.rows
            let markdown = session.view?.type == "Detail" ? session.view?.string("markdown") : nil
            guard rows.first != nil || markdown != nil else { return }
            let actions = session.actions.compactMap { $0.string("title") }.joined(separator: " | ")
            let summary = markdown.map { "markdown=\($0.prefix(60).debugDescription)" }
                ?? "rows=\(rows.count) first=\"\(rows[0].node.string("title") ?? "")\""
            print("SELFTEST OK: view=\(session.view?.type ?? "?") \(summary) actions=[\(actions)]")
            let describe = { (entries: [MenuEntry]) in
                entries.map { "\($0.section.map { "[\($0)] " } ?? "")\($0.node.string("title") ?? "?")\($0.isSubmenu ? " ›" : "")" }.joined(separator: ", ")
            }
            print("SELFTEST MENU: \(describe(session.menuEntries))")
            if let submenu = session.menuEntries.first(where: \.isSubmenu) {
                session.openSubmenu(submenu.node)
                print("SELFTEST SUBMENU: \(describe(session.menuEntries))")
                session.closeSubmenuOrMenu()
            }
            session.actionQuery = "copy"
            print("SELFTEST MENU SEARCH copy: \(describe(session.menuEntries))")
            session.forceStop()
            exit(0)
        }
    }
    session.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        print("SELFTEST FAIL: timed out; view=\(session.view?.type ?? "none") toast=\(session.toast?.title ?? "none")")
        session.forceStop()
        exit(1)
    }
    withExtendedLifetime(observer) { RunLoop.main.run() }
    exit(1)
}
