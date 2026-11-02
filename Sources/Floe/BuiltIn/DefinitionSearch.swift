//
//  DefinitionSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The dictionary answers for the query on screen. Root ranking never waits for a disk-backed lookup.
final class DefinitionSearch {
    typealias Lookup = @concurrent @Sendable (String) async -> String?
    typealias Completions = @MainActor @Sendable (String) -> [String]

    var lookup: Lookup
    /// The words that start with what was typed.
    var completions: Completions
    private(set) var definitions: [WordDefinition] = []
    private var word: String?
    private var task: Task<Void, Never>?

    init(lookup: @escaping Lookup = WordDefinition.entry, completions: @escaping Completions = WordDefinition.completions) {
        self.lookup = lookup
        self.completions = completions
    }

    deinit {
        task?.cancel()
    }

    var isSearching: Bool {
        task != nil
    }

    @discardableResult
    func search(_ context: SearchContext, onChange: @escaping () -> Void) -> Task<Void, Never>? {
        let wanted = context.text(after: context.definitionKeyword)
        guard wanted != word else { return task }
        cancel()
        guard let wanted else { return nil }
        word = wanted
        task = Task { [weak self, lookup, completions] in
            var found: [WordDefinition] = []
            // The word typed is read first: the spell checker's first answer after launch takes a moment.
            let exact = await lookup(wanted)
            let others = WordDefinition.words(for: wanted, completions: completions(wanted)).dropFirst()
            found += exact.map { [WordDefinition(word: wanted, entry: $0)] } ?? []
            for other in others where !Task.isCancelled {
                if let entry = await lookup(other) {
                    found.append(WordDefinition(word: other, entry: entry))
                }
            }
            guard let self, !Task.isCancelled, word == wanted else { return }
            definitions = found
            task = nil
            onChange()
        }
        return task
    }

    func cancel() {
        task?.cancel()
        task = nil
        word = nil
        definitions = []
    }

    func settled() async {
        await task?.value
    }
}
