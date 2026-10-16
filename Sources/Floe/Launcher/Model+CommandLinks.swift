//
//  Model+CommandLinks.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A raycast://extensions/<owner>/<extension>/<command> link, which extensions open to start a command.
struct CommandLink {
    let owner: String
    let extensionName: String
    let commandName: String
    /// Nil when the link carries none, so a command that takes arguments asks for them.
    let arguments: [String: Any]?

    /// Nil for every other raycast:// link: those name a feature of Raycast's own.
    init?(_ url: URL) {
        let names = url.pathComponents.filter { $0 != "/" }
        guard url.scheme?.lowercased() == "raycast", url.host() == "extensions", names.count == 3 else { return nil }
        owner = names[0]
        extensionName = names[1]
        commandName = names[2]
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let json = items?.first { $0.name == "arguments" }?.value
        arguments = json.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    /// Whether this link is for the command. An extension that names no owner is known by its name alone.
    func names(_ command: ExtensionCommand) -> Bool {
        command.extensionName == extensionName && command.name == commandName
            && (command.owner.map { $0.caseInsensitiveCompare(owner) == .orderedSame } ?? true)
    }
}

extension LauncherModel {
    /// Runs the command a link names when it is installed and enabled. Any other link is left to the system.
    func runCommandLink(_ url: URL) -> Bool {
        guard let link = CommandLink(url),
              let command = commands.first(where: { link.names($0) })
        else { return false }
        // Running a menu-bar command that has its status item would take the item away.
        if command.mode != "menu-bar" || !isInMenuBar(command) {
            runner.run(command, arguments: link.arguments)
        }
        return true
    }
}
