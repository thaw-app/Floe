//
//  Model+Setup.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Showing a command's setup form and running the command once it is filled in; the typed values are `SetupFormModel`'s.
extension LauncherModel {
    func beginSetup(_ request: SetupRequest) {
        setupForm.begin(request)
        setup = request
        panelHost.showPanel()
        focusToken += 1
    }

    func submitSetup() {
        guard let request = setup, let values = setupForm.validated(for: request) else { return }
        setup = nil
        switch request.kind {
        case .preferences:
            let command = request.command
            PreferenceStore.save(values, fields: request.asked(of: command.extensionPreferences), extensionName: command.extensionName, command: nil)
            PreferenceStore.save(values, fields: request.asked(of: command.commandPreferences), extensionName: command.extensionName, command: command)
            runner.run(command, arguments: request.arguments)
        case .arguments:
            runner.run(request.command, arguments: values)
        }
    }

    /// A command asked for its preferences in Settings, or to sign in, which Floe cannot do yet. For a sign-in
    /// the token it takes instead is asked for in a form, and the command runs again once it is filled in.
    func showPreferences(_ message: [String: Any], of session: ExtensionSession) {
        let command = session.command
        guard message["type"] as? String == "signIn" else {
            panelHost.hidePanel()
            panelHost.openSettings(.extensionPage(command.extensionName))
            return
        }
        guard let field = command.preferences.first(where: { $0.name == message["preference"] as? String }) else { return }
        let arguments = session.arguments
        runner.end(session)
        let provider = message["provider"] as? String ?? command.extensionTitle
        beginSetup(SetupRequest(command: command, kind: .preferences, fields: [field], provider: provider, arguments: arguments))
    }

    func cancelSetup() {
        setup = nil
        focusToken += 1
    }
}
