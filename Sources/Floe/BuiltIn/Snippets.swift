//
//  Snippets.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Text saved under a name and a keyword: pasted from the root search, or typed as its keyword anywhere.
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var keyword: String
    var text: String

    var firstLine: String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }

    /// The text with its placeholders filled in: {clipboard}, {date}, {time}, {datetime}, {uuid}, {day}.
    static func expand(_ text: String, clipboard: String, now: Date = Date(), uuid: UUID = UUID()) -> String {
        let replacements = [
            "{clipboard}": clipboard,
            "{date}": now.formatted(date: .abbreviated, time: .omitted),
            "{time}": now.formatted(date: .omitted, time: .shortened),
            "{datetime}": now.formatted(date: .abbreviated, time: .shortened),
            "{uuid}": uuid.uuidString,
            "{day}": now.formatted(.dateTime.weekday(.wide)),
        ]
        return replacements.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    /// Nil when a keyword can be used, otherwise why it can't.
    static func keywordProblem(_ keyword: String, id: UUID, among snippets: [Snippet]) -> String? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            return String(localized: "Keywords need at least 2 characters.", bundle: .floe)
        }
        if trimmed.contains(where: \.isWhitespace) {
            return String(localized: "Keywords can't contain spaces.", bundle: .floe)
        }
        if snippets.contains(where: { $0.id != id && $0.keyword == trimmed }) {
            return String(localized: "Another snippet uses that keyword.", bundle: .floe)
        }
        return nil
    }

    /// The snippet whose keyword the typed text ends with; the longest keyword wins.
    static func match(typed: String, in snippets: [Snippet]) -> Snippet? {
        snippets.filter { !$0.keyword.isEmpty && typed.hasSuffix($0.keyword) }.max { $0.keyword.count < $1.keyword.count }
    }

    /// Whether any key typed could expand a snippet. While none could, the keys of other apps are not listened to.
    static func canExpand(_ snippets: [Snippet], enabled: Bool) -> Bool {
        enabled && snippets.contains { !$0.keyword.isEmpty }
    }
}

/// Snippets and whether typed keywords expand, kept in Floe's support folder.
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published var snippets: [Snippet] = [] {
        didSet { save() }
    }

    @Published var expansionEnabled = true {
        didSet { save() }
    }

    private struct Saved: Codable {
        var snippets: [Snippet]
        var expansionEnabled: Bool
    }

    private let file: URL
    private var isLoading = false
    /// Called after each save. The process link sets it, to tell the other process.
    var onSaved: (() -> Void)?

    init(file: URL = Paths.support.appendingPathComponent("snippets.json")) {
        self.file = file
        reload()
    }

    /// Reads the file again, after another process saved it. Nothing is written back.
    func reload() {
        isLoading = true
        if let saved = JSONFile.read(Saved.self, from: file) {
            snippets = saved.snippets
            expansionEnabled = saved.expansionEnabled
        }
        isLoading = false
    }

    func expanded(_ snippet: Snippet) -> String {
        Snippet.expand(snippet.text, clipboard: NSPasteboard.general.string(forType: .string) ?? "")
    }

    func upsert(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
    }

    func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
    }

    private func save() {
        guard !isLoading, JSONFile.write(Saved(snippets: snippets, expansionEnabled: expansionEnabled), to: file) else { return }
        onSaved?()
    }
}
