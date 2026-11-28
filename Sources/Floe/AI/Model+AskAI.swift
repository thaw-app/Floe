//
//  Model+AskAI.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Showing and leaving Ask AI's answer view; the conversation is `AskAIModel`'s.
extension LauncherModel {
    /// Replaces the list with the answer to a question, as a conversation of its own: one that was open is dropped.
    /// The query stays, for when the view is left.
    func openAskAI(_ question: String) {
        let asking = AskAIModel(
            question: question,
            source: AskAI.configuredSource(settings),
            limit: .limit(for: settings.aiSource),
            request: askAIRequest
        )
        asking.host = modeHost { [weak self] in self?.closeAskAI() }
        enter(.askAI(asking))
        asking.ask()
    }

    /// Back to the root search. The request stops and the conversation is gone: nothing of it is saved.
    func closeAskAI() {
        guard modes.contains(.askAI) else { return }
        leave(.askAI)
        focusToken += 1
    }

    /// The answer view went off screen. Under another mode the conversation waits to be shown again; one no longer
    /// open stops.
    func leaveAskAI(_ asking: AskAIModel) {
        if !modes.holds(asking) {
            asking.leave()
        }
    }
}
