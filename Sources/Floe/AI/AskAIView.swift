//
//  AskAIView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// A conversation with the chosen source, laid out as every view with a field is: the field for the
/// next question, the questions and answers under it, and the bar. Return in an empty field copies the
/// answer, Return after typing asks, and Escape goes back to the search.
struct AskAIView: View {
    /// For leaving the view and the Actions menu. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    @ObservedObject var asking: AskAIModel

    var body: some View {
        PanelSections {
            SearchBar(
                placeholder: String(localized: "Ask a follow-up…", bundle: .floe, comment: "The prompt of the field above an AI answer, where the next question about it is typed."),
                text: $asking.draft,
                focusToken: asking.focus,
                isLoading: asking.isWorking
            ) { EmptyView() }
        } content: {
            // Compared by its values, so typing in the field draws none of the conversation again.
            AskAITranscript(
                turns: asking.turns,
                question: asking.question,
                shown: asking.shown,
                state: asking.state,
                source: asking.source,
                leftOutTurns: asking.leftOut > 0,
                scroll: asking.scroll
            ) { asking.ask() }
                .equatable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .actionPanel(launcher.actionPanel)
            bottomBar
        }
        // Something else took the panel: the request stops with the view.
        .onDisappear { launcher.leaveAskAI(asking) }
    }

    private var bottomBar: some View {
        PanelBottomBar {
            ShortcutHintButton(title: String(localized: "Back", bundle: .floe, comment: "A button that returns to the search.")) { launcher.closeAskAI() } hint: {
                KeyCapView(text: "esc")
            }
            Spacer(minLength: 0)
            ShortcutHintButton(title: String(localized: "Ask Again", bundle: .floe)) { asking.ask() } hint: {
                KeyCapView(text: "⌘")
                KeyCapView(text: "R")
            }
            ActionsButton(model: launcher) { $0.askAI?.actions() ?? [] }
            if !asking.shown.text.isEmpty {
                ShortcutHintButton(title: String(localized: "Paste Answer", bundle: .floe)) { asking.pasteAnswer() } hint: {
                    KeyCapView(text: "⌘")
                    KeyCapView(systemImage: "return")
                }
            }
            // Return has one meaning at a time, and only that one is shown with the key.
            switch asking.returnAction {
            case .askFollowUp:
                ShortcutHintButton(title: String(localized: "Ask", bundle: .floe, comment: "A verb on a button: send the question to AI.")) { asking.askFollowUp() } hint: {
                    KeyCapView(systemImage: "return")
                }
            case .copyAnswer:
                ShortcutHintButton(title: String(localized: "Copy Answer", bundle: .floe)) { asking.copyAnswer() } hint: {
                    KeyCapView(systemImage: "return")
                }
            case .askAgain, .nothing:
                EmptyView()
            }
        }
    }
}
