//
//  FallbackSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The fallbacks the user chose, under everything else and in their order, each handed what was typed.
/// One that cannot answer this search, such as Ask AI with no source, is left out.
struct FallbackSearchProvider: SearchProvider {
    var shell = ShellCommandSearchProvider()

    func contribution(for context: SearchContext) -> SearchContribution {
        let text = context.trimmed
        guard !text.isEmpty else { return SearchContribution() }
        let section = String(localized: "Fallbacks", bundle: .floe, comment: "A section title above the searches offered when nothing else matches.")
        let rows = Fallback.order(chosen: context.fallbacks, quicklinks: context.quicklinks).compactMap { fallback in
            item(for: fallback, text: text, context: context).map { RootResult(item: $0, section: section) }
        }
        return SearchContribution(appended: rows)
    }

    private func item(for fallback: Fallback, text: String, context: SearchContext) -> RootItem? {
        switch fallback {
        case .shell:
            return shell.guess(for: context)
        case .searchFiles:
            return .searchFiles(context.query)
        case .askAI:
            return context.canAskAI && AskAI.question(in: context) == nil ? .askAI(text) : nil
        case let .quicklink(id):
            guard let link = context.quicklinks.first(where: { $0.id == id }), Fallback.accepts(link) else { return nil }
            return .quicklink(link, queryText: text, fallback: true, keywordSearch: false)
        case let .command(id):
            guard let command = context.commands.first(where: { $0.id == id }), Fallback.accepts(command) else { return nil }
            return .fallbackCommand(command, text: text)
        }
    }
}
