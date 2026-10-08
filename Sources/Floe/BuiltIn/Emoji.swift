//
//  Emoji.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Foundation
import Synchronization

/// One emoji or symbol: the character to paste and its display name.
nonisolated struct EmojiResult: Sendable {
    let character: String
    let name: String
    /// The emoji before a skin tone was put on it. Its use is counted under this one, whatever the tone.
    var untoned: String?

    var id: String {
        Self.id(for: untoned ?? character)
    }

    /// The same emoji in a skin tone, when it is one that takes a tone.
    func toned(_ tone: EmojiSkinTone) -> EmojiResult {
        let toned = tone.applied(to: character)
        return toned == character ? self : EmojiResult(character: toned, name: name, untoned: character)
    }

    static func id(for character: String) -> String {
        "emoji:\(character)"
    }
}

/// The skin tone hands and people are shown and pasted in.
nonisolated enum EmojiSkinTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, light, mediumLight, medium, mediumDark, dark

    var id: String {
        rawValue
    }

    /// The tone's name, as the picker says it beside the hand.
    var label: String {
        switch self {
        case .none: String(localized: "Default", bundle: .floe, comment: "A skin tone for emoji: the yellow one, with no tone.")
        case .light: String(localized: "Light", bundle: .floe, comment: "A skin tone for emoji.")
        case .mediumLight: String(localized: "Medium-Light", bundle: .floe, comment: "A skin tone for emoji.")
        case .medium: String(localized: "Medium", bundle: .floe, comment: "A skin tone for emoji.")
        case .mediumDark: String(localized: "Medium-Dark", bundle: .floe, comment: "A skin tone for emoji.")
        case .dark: String(localized: "Dark", bundle: .floe, comment: "A skin tone for emoji.")
        }
    }

    /// The modifier Unicode puts after an emoji to tone it, U+1F3FB to U+1F3FF.
    var modifier: Unicode.Scalar? {
        switch self {
        case .none: nil
        case .light: "\u{1F3FB}"
        case .mediumLight: "\u{1F3FC}"
        case .medium: "\u{1F3FD}"
        case .mediumDark: "\u{1F3FE}"
        case .dark: "\u{1F3FF}"
        }
    }

    /// The emoji in this tone. Only one with a single person or hand in it is toned: a family or a
    /// handshake takes a tone for each of its people, and a guess at those draws as separate pictures.
    func applied(to emoji: String) -> String {
        guard let modifier else { return emoji }
        let scalars = Array(emoji.unicodeScalars)
        let bases = scalars.indices.filter { scalars[$0].properties.isEmojiModifierBase }
        guard bases.count == 1, let base = bases.first, !scalars.contains(where: \.properties.isEmojiModifier) else { return emoji }
        var toned = String.UnicodeScalarView(scalars[...base])
        toned.append(modifier)
        // A tone takes the place of the selector that asks for the picture form.
        let rest = scalars[(base + 1)...]
        toned.append(contentsOf: rest.first == "\u{FE0F}" ? rest.dropFirst() : rest)
        return String(toned)
    }
}

/// The emoji and symbol catalog. Entries come from Unicode scalar properties, not bundled data:
/// every named symbol scalar (which covers the pictographic emoji) becomes a searchable entry.
/// The table is built once, in the background; searches before it finishes find nothing yet.
nonisolated enum EmojiCatalog {
    struct Entry: Sendable {
        let character: String
        let name: String
        let searchText: String
        let keywords: [String]
    }

    private struct Cache {
        var entries: [Entry]?
        var preloadStarted = false
    }

    private static let cache = Mutex(Cache())

    /// Starts building the table off the caller's thread; safe to call more than once.
    static func preload() {
        let isFirst = cache.withLock { cache in
            defer { cache.preloadStarted = true }
            return !cache.preloadStarted
        }
        guard isFirst else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = entries()
        }
    }

    static func entries() -> [Entry] {
        if let cached = cache.withLock({ $0.entries }) {
            return cached
        }
        // Built outside the lock: two callers may both build, and the first to finish is kept.
        let built = build()
        return cache.withLock { cache in
            if let cached = cache.entries {
                return cached
            }
            cache.entries = built
            return built
        }
    }

    /// With an empty term: recent picks first, then common standbys. Otherwise the best
    /// name and keyword matches, nudged by how often and how recently each was used.
    static func search(term: String, frecency: (String) -> Double, limit: Int = 8) -> [EmojiResult] {
        let all = entries()
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            let recent = all
                .filter { frecency($0.character) > 0 }
                .min(count: limit) { frecency($0.character) > frecency($1.character) }
            let seen = Set(recent.map(\.character))
            let fill = commonCharacters
                .compactMap { character in all.first(where: { $0.character == character }) }
                .filter { !seen.contains($0.character) }
                .prefix(max(0, limit - recent.count))
            return (recent + fill).map { EmojiResult(character: $0.character, name: $0.name) }
        }
        return all
            .compactMap { entry -> (Entry, Double)? in
                guard let match = score(needle: needle, entry: entry) else { return nil }
                return (entry, Double(match) + min(20, frecency(entry.character) * 2))
            }
            .min(count: limit) { $0.1 > $1.1 }
            .map { EmojiResult(character: $0.0.character, name: $0.0.name) }
    }

    private static func score(needle: String, entry: Entry) -> Int? {
        // An exact keyword wins outright, so common names beat longer Unicode names.
        if entry.keywords.contains(needle) {
            return 1000
        }
        var best = Fuzzy.score(needle, entry.searchText)
        for keyword in entry.keywords {
            if let keywordScore = Fuzzy.score(needle, keyword) {
                best = max(best ?? 0, keywordScore)
            }
        }
        return best
    }

    private static func build() -> [Entry] {
        let symbols = CharacterSet.symbols
        var out: [Entry] = []
        out.reserveCapacity(8192)
        for value in UInt32(0) ... 0x10FFFF {
            guard let scalar = Unicode.Scalar(value), symbols.contains(scalar) else { continue }
            guard let rawName = scalar.properties.name else { continue }
            let character = String(scalar)
            out.append(Entry(
                character: character,
                name: rawName.capitalized,
                searchText: rawName.lowercased(),
                keywords: extraKeywords[character] ?? []
            ))
        }
        return out
    }

    /// Standbys shown for an empty query when there are no recents yet. Every one is a single
    /// named symbol scalar, so each is guaranteed to be in the table once it is built.
    private static let commonCharacters: [String] = [
        "🔥", "❤", "😀", "👍", "🎉", "✅", "❌", "⭐",
    ]

    /// Extra search words for common entries, keyed by character. The Unicode names alone miss
    /// the words people type ("fire" is covered by the FIRE scalar's name; "flame" is not).
    private static let extraKeywords: [String: [String]] = [
        "🔥": String(localized: "fire, flame, hot, lit", bundle: .floe, comment: "Words that find the symbol 🔥, separated by commas.").keywordList,
        "❤": String(localized: "heart, love", bundle: .floe, comment: "Words that find the symbol ❤, separated by commas.").keywordList,
        "😀": String(localized: "smile, happy, grin, grinning", bundle: .floe, comment: "Words that find the symbol 😀, separated by commas.").keywordList,
        "👍": String(localized: "thumbs up, thumbsup, like, approve, yes", bundle: .floe, comment: "Words that find the symbol 👍, separated by commas.").keywordList,
        "🎉": String(localized: "party, celebrate, celebration, tada, congrats", bundle: .floe, comment: "Words that find the symbol 🎉, separated by commas.").keywordList,
        "✅": String(localized: "check, checkmark, done, yes, tick", bundle: .floe, comment: "Words that find the symbol ✅, separated by commas.").keywordList,
        "❌": String(localized: "cross, x, no, wrong, delete", bundle: .floe, comment: "Words that find the symbol ❌, separated by commas.").keywordList,
        "⭐": String(localized: "star, favorite, favourite", bundle: .floe, comment: "Words that find the symbol ⭐, separated by commas.").keywordList,
        "©": String(localized: "copyright", bundle: .floe, comment: "Words that find the symbol ©, separated by commas.").keywordList,
        "®": String(localized: "registered", bundle: .floe, comment: "Words that find the symbol ®, separated by commas.").keywordList,
        "™": String(localized: "trademark, tm", bundle: .floe, comment: "Words that find the symbol ™, separated by commas.").keywordList,
        "→": String(localized: "arrow, right, rightarrow", bundle: .floe, comment: "Words that find the symbol →, separated by commas.").keywordList,
        "←": String(localized: "arrow, left, leftarrow", bundle: .floe, comment: "Words that find the symbol ←, separated by commas.").keywordList,
        "↑": String(localized: "arrow, up, uparrow", bundle: .floe, comment: "Words that find the symbol ↑, separated by commas.").keywordList,
        "↓": String(localized: "arrow, down, downarrow", bundle: .floe, comment: "Words that find the symbol ↓, separated by commas.").keywordList,
        "✓": String(localized: "check, checkmark, tick", bundle: .floe, comment: "Words that find the symbol ✓, separated by commas.").keywordList,
        "♥": String(localized: "heart, suit, hearts", bundle: .floe, comment: "Words that find the symbol ♥, separated by commas.").keywordList,
        "☀": String(localized: "sun, sunny, weather", bundle: .floe, comment: "Words that find the symbol ☀, separated by commas.").keywordList,
        "⚡": String(localized: "lightning, bolt, zap, fast", bundle: .floe, comment: "Words that find the symbol ⚡, separated by commas.").keywordList,
        "€": String(localized: "euro, money, currency", bundle: .floe, comment: "Words that find the symbol €, separated by commas.").keywordList,
    ]
}
