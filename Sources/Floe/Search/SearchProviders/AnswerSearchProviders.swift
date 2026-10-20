//
//  AnswerSearchProviders.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The answer to a query that is arithmetic or a conversion.
struct CalculatorSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard let row = context.calculation else { return SearchContribution() }
        let preview = row.preview
        let item = RootItem.calculator(expression: row.expression, result: preview.result, error: preview.error, attributedResult: preview.attributedResult)
        return SearchContribution(pinned: [RootResult(item: item, section: String(localized: "Calculator", bundle: .floe))])
    }
}

/// `note buy milk` leads with the note it would make, and the to-do word alone with the row that opens the day's note.
struct NoteSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        if let note = Notes.request(in: context.trimmed, app: context.notesApp) {
            return SearchContribution(pinned: [RootResult(item: .note(note.action, text: note.text), section: nil)])
        }
        guard Notes.opensDaysNote(context.trimmed, app: context.notesApp) else { return SearchContribution() }
        return SearchContribution(pinned: [RootResult(item: .note(.today, text: ""), section: nil)])
    }
}

/// A script matches when the query starts with its title and the rest is its arguments.
struct ScriptArgumentsSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard !context.query.isEmpty else { return SearchContribution() }
        let hits = context.scripts.filter { $0.argumentsText(in: context.query) != nil }
        return SearchContribution(pinned: hits.map { RootResult(item: .script($0), section: nil) })
    }
}
