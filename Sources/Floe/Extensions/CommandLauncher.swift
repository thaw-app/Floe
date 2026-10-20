//
//  CommandLauncher.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Answers `launchCommand`: finds the command, of the caller's extension or of another one installed,
/// and starts it as the user would or in the background. One per process, made where the process starts.
final class CommandLauncher {
    typealias Start = (_ command: ExtensionCommand, _ arguments: [String: Any], _ context: [String: Any]?) -> Void

    static var shared: CommandLauncher?

    private let commands: () -> [ExtensionCommand]
    private let userInitiated: Start
    private let background: Start

    init(commands: @escaping () -> [ExtensionCommand], userInitiated: @escaping Start, background: @escaping Start) {
        self.commands = commands
        self.userInitiated = userInitiated
        self.background = background
    }

    /// The messages go to the extension's own code, which shows or logs them, so they stay in English.
    func launch(_ params: [String: Any], from caller: ExtensionCommand) throws {
        guard let name = params["name"] as? String, !name.isEmpty else {
            throw RequestRefusal(errorDescription: "launchCommand needs the name of a command.")
        }
        let extensionName = params["extensionName"] as? String ?? caller.extensionName
        guard let command = commands().first(where: { $0.extensionName == extensionName && $0.name == name }) else {
            throw RequestRefusal(errorDescription: extensionName == caller.extensionName
                ? "This extension has no command \"\(name)\" that is switched on in Floe."
                : "The extension \"\(extensionName)\" isn't installed, or its command \"\(name)\" is switched off.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let context = params["context"] as? [String: Any]
        guard params["type"] as? String == "background" else {
            userInitiated(command, arguments, context)
            return
        }
        guard command.mode != "view" else {
            throw RequestRefusal(errorDescription: "\"\(name)\" has a view, so it can only be launched by the user, not in the background.")
        }
        background(command, arguments, context)
    }

    /// A command's arguments as JSON, for a request that carries them, and back.
    static func data(_ object: [String: Any]?) -> Data? {
        guard let object, JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    static func object(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
