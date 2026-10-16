//
//  IntentHandler.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What Floe's App Intents can ask of the process the system delivered them to. The system makes the intents
/// itself, so nothing can be handed to them; each process registers its handler instead, where it is wired.
@MainActor
struct IntentHandler {
    /// The commands an intent may run: those of the extensions switched on, once the catalog has loaded.
    var runnableCommands: () async -> [ExtensionCommand]
    /// Shows the launcher with a request, through the resident's lifecycle gate.
    var present: (PanelRequest) -> Void
    /// Counts a run, as running it from the launcher does.
    var recordUse: (String) -> Void

    /// The handler of this process. Nil while it is still starting.
    static var current: IntentHandler?

    /// Answers from a launcher model's catalog and usage, and presents through present.
    static func serving(_ model: LauncherModel, present: @escaping (PanelRequest) -> Void) -> IntentHandler {
        IntentHandler(
            runnableCommands: {
                await model.catalog.waitForCommands()
                return model.commands
            },
            present: present,
            recordUse: { model.usage.recordUse(of: $0) }
        )
    }
}
