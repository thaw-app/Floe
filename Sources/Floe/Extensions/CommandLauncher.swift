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

    struct Refusal: LocalizedError {
        let errorDescription: String?
    }

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
            throw Refusal(errorDescription: "launchCommand needs the name of a command.")
        }
        let extensionName = params["extensionName"] as? String ?? caller.extensionName
        guard let command = commands().first(where: { $0.extensionName == extensionName && $0.name == name }) else {
            throw Refusal(errorDescription: extensionName == caller.extensionName
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
            throw Refusal(errorDescription: "\"\(name)\" has a view, so it can only be launched by the user, not in the background.")
        }
        background(command, arguments, context)
    }

    /// The panel's background launch, run here in the resident.
    func launchInBackground(id: String, arguments: Data?, context: Data?) {
        guard let command = commands().first(where: { $0.id == id }) else { return }
        background(command, Self.object(arguments) ?? [:], Self.object(context))
    }

    /// A dictionary as the JSON that crosses between the processes, and back.
    static func data(_ object: [String: Any]?) -> Data? {
        guard let object, JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    static func object(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

extension CommandLauncher {
    /// The panel's: it runs what the user launches, and hands background launches to the resident, which runs
    /// what the panel never does.
    static func panel(model: LauncherModel, send: @escaping (PanelPacket) -> Void) -> CommandLauncher {
        CommandLauncher(
            commands: { [weak model] in model?.commands ?? [] },
            userInitiated: { [weak model] command, arguments, context in model?.runner.run(command, arguments: arguments, context: context) },
            background: { command, arguments, context in
                send(.launchInBackground(command.id, arguments: data(arguments), context: data(context)))
            }
        )
    }
}

extension ExtensionSession {
    /// Answers `command.launch` once the command has been started, or with why it could not be.
    func answerLaunch(id: Int, params: [String: Any]) {
        var reply: [String: Any] = ["type": "reply", "id": id]
        do {
            guard let launcher = CommandLauncher.shared else {
                throw CommandLauncher.Refusal(errorDescription: "Floe can't launch commands from here.")
            }
            try launcher.launch(params, from: command)
            reply["result"] = NSNull()
        } catch {
            reply["error"] = error.localizedDescription
        }
        send(reply)
    }
}
