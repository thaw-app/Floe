//
//  Picker.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One line of the picker's input, with the place it had there.
struct PickItem: Identifiable, Equatable {
    /// Zero-based position among every line of the input, blank ones included.
    let index: Int
    let text: String
    /// A line with tabs is a row with columns: the first is its title.
    let title: String
    /// The columns after the first, shown beside the title. Nil for a line without a tab.
    let detail: String?

    var id: Int {
        index
    }

    /// The line is split here once: a search reads the title and the detail of every item on every keystroke.
    init(index: Int, text: String) {
        self.index = index
        self.text = text
        let columns = text.split(separator: "\t", omittingEmptySubsequences: false)
        title = columns.first.map(String.init) ?? text
        let rest = columns.dropFirst().filter { !$0.isEmpty }
        detail = rest.isEmpty ? nil : rest.joined(separator: "  ")
    }
}

/// How `Floe --pick` ends, as the exit status the calling script sees.
enum PickExit: Int32 {
    case chosen = 0
    case cancelled = 1
    /// sysexits' EX_USAGE: the command was called the wrong way.
    case usage = 64
}

/// The picker without its window: what the input holds, what a query leaves of it, and what a choice prints.
enum PickList {
    static let usage = "Floe --pick reads the items to choose from on standard input, one per line: ls | Floe --pick. A tab splits a line into a title and what is shown beside it; the whole line is printed."

    /// A line of nothing but spaces is blank too. The text is kept as it came, so the caller gets its own line back.
    static func items(from input: String) -> [PickItem] {
        input.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in
                line.allSatisfy(\.isWhitespace) ? nil : PickItem(index: index, text: String(line))
            }
    }

    /// No query lists everything in input order. With one, the best match comes first and equal scores keep input order.
    static func matches(_ items: [PickItem], query: String) -> [PickItem] {
        guard !query.isEmpty else { return items }
        let scored: [(item: PickItem, score: Int)] = items.compactMap { item in
            // The title counts for more than the columns beside it.
            [Fuzzy.score(query, item.title), item.detail.flatMap { Fuzzy.score(query, $0) }.map { $0 - 10 }].compactMap(\.self).max().map { (item, $0) }
        }
        // The position breaks ties, so the order does not depend on the sort being stable.
        let ordered = scored.sorted { first, second in
            first.score == second.score ? first.item.index < second.item.index : first.score > second.score
        }
        return ordered.map(\.item)
    }

    static func output(for item: PickItem, printsIndex: Bool) -> String {
        printsIndex ? String(item.index) : item.text
    }

    /// The bottom bar's count: everything while there is no query, then how much of it still matches.
    static func countLabel(shown: Int, total: Int, isFiltered: Bool) -> String {
        if isFiltered {
            return String(localized: "\(shown) of \(total)", bundle: .floe, comment: "How many lines of a list match what was typed: 3 of 40.")
        }
        return String(localized: "\(total) items", bundle: .floe, comment: "How many lines a list has.")
    }

    /// The selection after an arrow, page or home/end key, kept inside the list.
    static func selection(_ selection: Int, movedBy delta: Int, count: Int) -> Int {
        max(0, min(count - 1, selection + delta))
    }
}
