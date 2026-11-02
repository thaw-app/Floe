//
//  WordDefinition.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import CoreServices
import Foundation

/// What the Mac's dictionaries say about a word typed after `define`.
nonisolated struct WordDefinition: Hashable, Sendable {
    static let keyword = "define"
    /// How many words a search lists, the one typed among them.
    static let listLimit = 8

    var word: String
    /// The entry on one line, as a row shows it. It starts with its headword.
    var text: String
    /// The entry as the dictionary wrote it, to read in full.
    var entry: String

    /// The link that opens the word in the Dictionary app.
    var link: URL? {
        word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])).flatMap { URL(string: "dict://\($0)") }
    }

    init(word: String, entry: String) {
        self.word = word
        text = entry.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        self.entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Words the search already answers to. A scope would take the query before the dictionary is asked.
    @MainActor
    private static let takenKeywords: Set<String> = {
        let words = KeywordHint.all.map(\.keyword) + CommandPrefix.allCases.map(\.rawValue) + [KeywordSearchScope.word, KeywordSearchScope.mark]
        return Set(words.map { $0.lowercased() }).subtracting([keyword])
    }()

    @MainActor
    static func isTaken(_ setting: String) -> Bool {
        takenKeywords.contains(setting.lowercased())
    }

    /// The keyword a setting names: its first word, or `define` when it is empty or the search already answers to it.
    @MainActor
    static func keyword(from setting: String) -> String {
        guard let word = setting.split(whereSeparator: \.isWhitespace).first.map({ $0.lowercased() }), !isTaken(word) else { return keyword }
        return word
    }

    /// The words to look up: the one typed, then those that start with it, without possessives such as tide's.
    static func words(for typed: String, completions: [String]) -> [String] {
        var seen: Set = [typed.lowercased()]
        var words = [typed]
        for word in completions where words.count < listLimit && !word.contains("'") && seen.insert(word.lowercased()).inserted {
            words.append(word)
        }
        return words
    }

    /// The words the Mac's spell checker knows that start with what was typed, likeliest first. It works on the main
    /// thread, and nothing leaves the Mac.
    @MainActor
    static func completions(of typed: String) -> [String] {
        let range = NSRange(location: 0, length: (typed as NSString).length)
        return NSSpellChecker.shared.completions(forPartialWordRange: range, in: typed, language: nil, inSpellDocumentWithTag: 0) ?? []
    }

    /// The entry of the dictionaries switched on in the Dictionary app, in their order. Nil when none has the word.
    /// Nothing leaves the Mac: the dictionaries are on disk.
    @concurrent
    static func entry(for word: String) async -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        return DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
    }
}

/// `define tide` leads with what the dictionary says, and `define tid` with the words that start with it.
struct DefinitionSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard let word = context.text(after: context.definitionKeyword) else { return SearchContribution() }
        let found = context.definitions.filter { $0.word.lowercased().hasPrefix(word.lowercased()) && !$0.text.isEmpty }
        return SearchContribution(pinned: found.map { RootResult(item: .definition($0), section: nil) })
    }
}
