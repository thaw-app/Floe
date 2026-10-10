//
//  Quicklinks.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import Combine
import Foundation

struct Quicklink: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var keyword: String
    /// May contain {query}, replaced with the percent-encoded search text.
    var url: String
    var isFallback: Bool
    var symbol: String

    init(id: UUID = UUID(), name: String, keyword: String, url: String, isFallback: Bool = false, symbol: String = "magnifyingglass") {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.url = url
        self.isFallback = isFallback
        self.symbol = symbol
    }

    /// Whether the link is a search, with text to type after its keyword, and not one page to open.
    var takesQuery: Bool {
        url.contains("{query}")
    }
}

final class QuicklinkStore: ObservableObject {
    static let shared = QuicklinkStore()

    @Published var links: [Quicklink] {
        didSet { save() }
    }

    private let file: URL
    private var isLoading = false
    /// Called after each save. The process link sets it, to tell the other process.
    var onSaved: (() -> Void)?

    init(file: URL = Paths.support.appendingPathComponent("quicklinks.json")) {
        self.file = file
        links = Self.stored(in: file) ?? Self.defaults
    }

    private static func stored(in file: URL) -> [Quicklink]? {
        JSONFile.read([Quicklink].self, from: file)
    }

    /// Reads the file again, after another process saved it. Nothing is written back.
    func reload() {
        guard let stored = Self.stored(in: file) else { return }
        isLoading = true
        links = stored
        isLoading = false
    }

    /// The same id on every Mac, so the links Floe comes with are one link to settings sync and not one per Mac.
    private static func defaultID(_ number: Int) -> UUID {
        UUID(uuidString: "F10E0000-0000-4000-8000-00000000000\(number)") ?? UUID()
    }

    static let defaults: [Quicklink] = [
        Quicklink(
            id: defaultID(1),
            name: "Google",
            keyword: "g",
            url: "https://www.google.com/search?q={query}",
            isFallback: true,
            symbol: "magnifyingglass"
        ),
        Quicklink(
            id: defaultID(2),
            name: "DuckDuckGo",
            keyword: "ddg",
            url: "https://duckduckgo.com/?q={query}",
            symbol: "magnifyingglass.circle"
        ),
        Quicklink(
            id: defaultID(3),
            name: "GitHub",
            keyword: "gh",
            url: "https://github.com/search?q={query}",
            symbol: "chevron.left.forwardslash.chevron.right"
        ),
        Quicklink(
            id: defaultID(4),
            name: "YouTube",
            keyword: "yt",
            url: "https://www.youtube.com/results?search_query={query}",
            symbol: "play.rectangle"
        ),
        Quicklink(
            id: defaultID(5),
            name: "Wikipedia",
            keyword: "wiki",
            url: "https://en.wikipedia.org/wiki/Special:Search?search={query}",
            symbol: "book"
        ),
        Quicklink(
            id: defaultID(6),
            name: "Apple Maps",
            keyword: "maps",
            url: "maps://?q={query}",
            symbol: "map"
        ),
        Quicklink(
            id: defaultID(7),
            name: String(localized: "Translate", bundle: .floe, comment: "The name of the quicklink that opens Google Translate."),
            keyword: "tr",
            url: "https://translate.google.com/?text={query}",
            symbol: "translate"
        ),
    ]

    func add(_ link: Quicklink) {
        links.append(link)
    }

    func update(_ link: Quicklink) {
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
        links[index] = link
    }

    func remove(_ link: Quicklink) {
        links.removeAll { $0.id == link.id }
    }

    func move(_ link: Quicklink, by offset: Int) {
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
        let destination = min(max(index + offset, 0), links.count - 1)
        guard destination != index else { return }
        links.move(fromOffsets: IndexSet(integer: index), toOffset: destination > index ? destination + 1 : destination)
    }

    /// Fallback links in user order.
    var fallbacks: [Quicklink] {
        links.filter(\.isFallback)
    }

    /// True when no other link (besides `ignoring`) already uses this keyword.
    func isKeywordUnique(_ keyword: String, ignoring id: UUID? = nil) -> Bool {
        let lowered = keyword.lowercased()
        return !links.contains { $0.id != id && $0.keyword.lowercased() == lowered }
    }

    private func save() {
        guard !isLoading else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(links) {
            try? data.write(to: file, options: .atomic)
            onSaved?()
        }
    }
}

/// Replaces {query} in the link's URL with the percent-encoded query text.
/// Links without the placeholder open as-is.
func url(for link: Quicklink, query: String) -> URL? {
    guard link.url.contains("{query}") else { return URL(string: link.url) }
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    return URL(string: link.url.replacingOccurrences(of: "{query}", with: encoded))
}
