//
//  Fuzzy.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

/// What the matcher needs from one unit of text, so ASCII can run on bytes and the rest on characters.
nonisolated protocol FuzzyUnit: Equatable {
    var isWordUnit: Bool { get }
    var isUppercaseUnit: Bool { get }
    var isLowercaseUnit: Bool { get }
}

nonisolated extension UInt8: FuzzyUnit {
    var isWordUnit: Bool {
        isLowercaseUnit || isUppercaseUnit || (0x30 ... 0x39).contains(self)
    }

    var isUppercaseUnit: Bool {
        (0x41 ... 0x5A).contains(self)
    }

    var isLowercaseUnit: Bool {
        (0x61 ... 0x7A).contains(self)
    }

    var asciiLowercased: UInt8 {
        isUppercaseUnit ? self | 0x20 : self
    }
}

nonisolated extension Character: FuzzyUnit {
    var isWordUnit: Bool {
        isLetter || isNumber
    }

    var isUppercaseUnit: Bool {
        isUppercase
    }

    var isLowercaseUnit: Bool {
        isLowercase
    }
}

nonisolated extension Fuzzy {
    typealias Match = (score: Int, matched: [Int])

    /// Scattered matches are graded from `scatteredFloor` up to 54, always under a substring's 55.
    static let substringScore = 55
    private static let scatteredFloor = 10
    /// Points for one matched character: at a word start, or straight after the previous match.
    private static let boundaryPoints = 10
    private static let runPoints = 8
    /// A match that starts within the first few characters earns up to this many extra points.
    private static let earlyPoints = 4
    /// Scales the per-character points so a perfect scattered match lands exactly on 54.
    private static let pointScale = 4
    private static let unreachable = Int.min / 2
    /// The most cells of query by candidate a scattered match keeps to say where its letters are. The table is
    /// built on the main thread as a row is drawn, so a longer pair is scored the same and shown without a highlight.
    static let positionBudget = 1 << 16

    /// The score and the offsets of the matched characters in `candidate`, counted in characters.
    static func match(_ query: String, _ candidate: String) -> Match? {
        evaluate(query, candidate, wantPositions: true)
    }

    /// `scattered` false stops at a run of characters: a caller that would drop a scattered match skips its cost.
    static func evaluate(_ query: String, _ candidate: String, wantPositions: Bool, scattered: Bool = true) -> Match? {
        // A carriage return can join the next byte into one character, which would shift the offsets.
        let isPlain = { (byte: UInt8) in byte < 0x80 && byte != 0x0D }
        if query.utf8.allSatisfy(isPlain), candidate.utf8.allSatisfy(isPlain) {
            let needle = query.utf8.map(\.asciiLowercased)
            let text = candidate.utf8.map(\.asciiLowercased)
            return evaluate(needle, in: text, original: { Array(candidate.utf8) }, wantPositions: wantPositions, allowScattered: scattered)
        }
        let text = Array(candidate.lowercased())
        return evaluate(Array(query.lowercased()), in: text, original: { Array(candidate) }, wantPositions: wantPositions, allowScattered: scattered)
    }

    private static func evaluate<Unit: FuzzyUnit>(
        _ needle: [Unit],
        in text: [Unit],
        original: () -> [Unit],
        wantPositions: Bool,
        allowScattered: Bool
    ) -> Match? {
        // Every tier needs the letters in order, so most candidates leave here without further work.
        guard isSubsequence(needle, of: text) else { return nil }
        if let tiered = tiered(needle, in: text, wantPositions: wantPositions) {
            return tiered
        }
        guard allowScattered else { return nil }
        let cased = original()
        // Lowercasing can change the length in rare scripts; without the original case there are no humps.
        let humps = cased.count == text.count ? cased : text
        let boundaries = text.indices.map { index in
            guard index > 0 else { return text[index].isWordUnit }
            return (text[index].isWordUnit && !text[index - 1].isWordUnit)
                || (humps[index].isUppercaseUnit && humps[index - 1].isLowercaseUnit)
        }
        return scattered(needle, in: text, boundaries: boundaries, wantPositions: wantPositions)
    }

    private static func isSubsequence<Unit: FuzzyUnit>(_ needle: [Unit], of text: [Unit]) -> Bool {
        guard needle.count <= text.count else { return false }
        var matched = 0
        for unit in text where matched < needle.count && unit == needle[matched] {
            matched += 1
        }
        return matched == needle.count
    }

    /// The four fixed tiers: prefix, word prefix, initials, substring.
    private static func tiered<Unit: FuzzyUnit>(_ needle: [Unit], in text: [Unit], wantPositions: Bool) -> Match? {
        let count = needle.count
        func run(from start: Int) -> [Int] {
            wantPositions ? Array(start ..< start + count) : []
        }
        if text.starts(with: needle) {
            return (100 - min(text.count - count, 20), run(from: 0))
        }
        let wordStarts = text.indices.filter { text[$0].isWordUnit && ($0 == 0 || !text[$0 - 1].isWordUnit) }
        if needle.allSatisfy(\.isWordUnit), let start = wordStarts.first(where: { text[$0...].starts(with: needle) }) {
            return (75, run(from: start))
        }
        if wordStarts.count >= count, zip(wordStarts, needle).allSatisfy({ text[$0] == $1 }) {
            return (70, wantPositions ? Array(wordStarts.prefix(count)) : [])
        }
        if let start = (0 ... text.count - count).first(where: { text[$0...].starts(with: needle) }) {
            return (substringScore, run(from: start))
        }
        return nil
    }

    /// The best alignment of letters that are in order but not together, by dynamic programming:
    /// each row holds the best total with that query letter placed at each position of the text.
    private static func scattered<Unit: FuzzyUnit>(
        _ needle: [Unit],
        in text: [Unit],
        boundaries: [Bool],
        wantPositions: Bool
    ) -> Match {
        let count = needle.count
        let length = text.count
        var previous = text.indices.map { column -> Int in
            guard text[column] == needle[0] else { return unreachable }
            return (boundaries[column] ? boundaryPoints * pointScale : 0) + count * max(0, earlyPoints - column)
        }
        var current = previous
        let wantPositions = wantPositions && count * length <= positionBudget
        var origins = wantPositions ? [Int](repeating: -1, count: count * length) : []
        for row in 1 ..< count {
            // The best total of the previous letter anywhere left of the adjacent position.
            var gapBest = unreachable
            var gapOrigin = -1
            for column in 0 ..< length {
                if column >= 2, previous[column - 2] > gapBest {
                    gapBest = previous[column - 2]
                    gapOrigin = column - 2
                }
                guard text[column] == needle[row] else {
                    current[column] = unreachable
                    continue
                }
                let bonus = boundaries[column] ? boundaryPoints : 0
                let adjacent = column >= 1 ? previous[column - 1] + max(bonus, runPoints) * pointScale : unreachable
                let apart = gapBest + bonus * pointScale
                // Real totals are never negative, so anything below zero came from an unreachable cell.
                current[column] = max(adjacent, apart) < 0 ? unreachable : max(adjacent, apart)
                if wantPositions {
                    origins[row * length + column] = apart > adjacent ? gapOrigin : column - 1
                }
            }
            swap(&previous, &current)
        }
        // The first of equal totals wins, so ties go to the leftmost alignment.
        var end = 0
        for column in 1 ..< length where previous[column] > previous[end] {
            end = column
        }
        let score = min(scatteredFloor + previous[end] / count, substringScore - 1)
        guard wantPositions else { return (score, []) }
        var matched = [Int](repeating: end, count: count)
        for row in stride(from: count - 1, to: 0, by: -1) {
            end = origins[row * length + end]
            matched[row - 1] = end
        }
        return (score, matched)
    }
}
