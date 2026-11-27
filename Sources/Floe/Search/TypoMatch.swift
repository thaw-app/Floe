//
//  TypoMatch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

/// A last try for an app the search would drop: the query as the start of its name, or of a word in it, with a
/// letter or two wrong, missing, extra or swapped. Only for plain ASCII names and queries.
nonisolated struct TypoMatch {
    private let needle: [UInt8]
    private let allowed: Int

    /// Nil for a query too short for any typo, or not plain ASCII. Made once for a query and asked about each app.
    init?(_ query: String) {
        allowed = Self.allowance(forLength: query.utf8.count)
        guard allowed > 0, query.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
        needle = query.utf8.map(\.asciiLowercased)
    }

    /// How many typos a query of this many characters may hold: none under 4, one up to 6, two from 7.
    static func allowance(forLength count: Int) -> Int {
        switch count {
        case ..<4: 0
        case ..<7: 1
        default: 2
        }
    }

    static func score(_ query: String, _ name: String) -> Int? {
        TypoMatch(query)?.score(name)
    }

    /// From 9 down to 5, under the 10 of the weakest match that works without typos. Fewer typos score higher, and
    /// so does the start of the name over a later word.
    func score(_ name: String) -> Int? {
        guard name.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
        let text = name.utf8.map(\.asciiLowercased)
        var rows = Rows(columns: needle.count + allowed + 1)
        var best: Int?
        for start in text.indices where text[start].isWordUnit && (start == 0 || !text[start - 1].isWordUnit) {
            // A start with no typos at all comes from a query with symbols, which the tiers don't match at a word start.
            guard let found = typos(startOf: text[start...], rows: &rows) else { continue }
            best = max(best ?? 0, 9 - (max(found, 1) - 1) * 3 - (start == 0 ? 0 : 1))
        }
        return best
    }

    /// Three rows of the table, kept for every start of one name: the two before the one being filled.
    private struct Rows {
        var beforeLast, last, current: [Int]

        init(columns: Int) {
            beforeLast = [Int](repeating: 0, count: columns)
            last = beforeLast
            current = beforeLast
        }
    }

    /// The fewest typos between the query and any start of the text, when that is within the allowance. A swap of
    /// two neighbouring letters counts as one, as in the optimal string alignment distance.
    private func typos(startOf text: ArraySlice<UInt8>, rows: inout Rows) -> Int? {
        let shortest = max(needle.count - allowed, 0)
        guard text.count >= shortest else { return nil }
        let text = text.prefix(needle.count + allowed)
        let base = text.startIndex
        let columns = text.count + 1
        for column in 0 ..< columns {
            rows.last[column] = column
        }
        for index in 1 ... needle.count {
            rows.current[0] = index
            for column in 1 ..< columns {
                let letter = text[base + column - 1]
                let substitution = rows.last[column - 1] + (needle[index - 1] == letter ? 0 : 1)
                rows.current[column] = min(rows.last[column] + 1, rows.current[column - 1] + 1, substitution)
                if index > 1, column > 1, needle[index - 1] == text[base + column - 2], needle[index - 2] == letter {
                    rows.current[column] = min(rows.current[column], rows.beforeLast[column - 2] + 1)
                }
            }
            (rows.beforeLast, rows.last, rows.current) = (rows.last, rows.current, rows.beforeLast)
        }
        // Any start of the text will do, from a few letters short of the query to a few past it.
        guard let fewest = rows.last[shortest ..< columns].min(), fewest <= allowed else { return nil }
        return fewest
    }
}
