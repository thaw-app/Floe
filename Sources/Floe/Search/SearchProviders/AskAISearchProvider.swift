//
//  AskAISearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `ask why is the sky blue` leads with the question; any other text can be asked as a fallback.
/// Neither is offered while no source can answer.
struct AskAISearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard context.canAskAI, !context.trimmed.isEmpty, let question = AskAI.question(in: context) else { return SearchContribution() }
        return SearchContribution(pinned: [RootResult(item: .askAI(question), section: nil)])
    }
}
