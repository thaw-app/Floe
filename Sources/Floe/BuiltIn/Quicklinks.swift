//
//  Quicklinks.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import AppKit
import Combine

struct Quicklink: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var keyword: String
    /// May contain {query}, replaced with the percent-encoded search text, and {selection} and {clipboard}, read when it opens.
    var url: String
    /// Whether the link was a fallback before the Fallbacks page: it seeds the order until the user chooses one there.
    var isFallback: Bool
    var symbol: String
    /// The app the link opens in, whatever its kind; nil opens it as any link of its kind opens.
    var openWith: AppChoice?

    init(
        id: UUID = UUID(),
        name: String,
        keyword: String,
        url: String,
        isFallback: Bool = false,
        symbol: String = "magnifyingglass",
        openWith: AppChoice? = nil
    ) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.url = url
        self.isFallback = isFallback
        self.symbol = symbol
        self.openWith = openWith
    }

    /// Whether the link is a search, with text to type after its keyword, and not one page to open.
    var takesQuery: Bool {
        url.contains("{query}")
    }

    /// Whether the link reads the selection or the clipboard when it opens.
    var fillsOnOpening: Bool {
        url.contains("{selection}") || url.contains("{clipboard}")
    }
}

/// What a link's {selection} and {clipboard} hold as it opens.
struct QuicklinkFills: Equatable {
    var selection = ""
    var clipboard = ""
}

/// Where a link's {selection} and {clipboard} are read from.
struct QuicklinkFillReader {
    var selection: () async throws -> String
    var clipboard: () -> String

    static var system: QuicklinkFillReader {
        QuicklinkFillReader(selection: selectedText, clipboard: { NSPasteboard.general.string(forType: .string) ?? "" })
    }

    private static func selectedText() async throws -> String {
        try await SelectedText.current()
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

    /// True when no other link (besides `ignoring`) already uses this keyword.
    func isKeywordUnique(_ keyword: String, ignoring id: UUID? = nil) -> Bool {
        let lowered = keyword.lowercased()
        return !links.contains { $0.id != id && $0.keyword.lowercased() == lowered }
    }

    /// Nil when the link can be kept, otherwise why it can't: Settings and extensions keep links by the same rules.
    func problem(with link: Quicklink, ignoring id: UUID? = nil) -> String? {
        let keyword = link.keyword.trimmingCharacters(in: .whitespaces)
        if link.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Enter a name.", bundle: .floe)
        }
        if keyword.isEmpty {
            return String(localized: "Enter a keyword.", bundle: .floe)
        }
        if keyword.contains(where: \.isWhitespace) {
            return String(localized: "Keywords cannot contain spaces.", bundle: .floe)
        }
        if !isKeywordUnique(keyword, ignoring: id) {
            return String(localized: "That keyword is already used.", bundle: .floe)
        }
        guard let url = URL(string: link.url), let scheme = url.scheme, !scheme.isEmpty else {
            return String(localized: "Enter a URL with a scheme, like https://.", bundle: .floe)
        }
        return nil
    }

    private func save() {
        guard !isLoading, JSONFile.write(links, to: file) else { return }
        onSaved?()
    }
}

/// Replaces {query}, {selection} and {clipboard} in the link's URL with their percent-encoded text.
/// Links without them open as-is.
func url(for link: Quicklink, query: String, fills: QuicklinkFills = QuicklinkFills()) -> URL? {
    let values = ["query": query, "selection": fills.selection, "clipboard": fills.clipboard]
    var text = ""
    var rest = link.url[...]
    while let match = rest.firstMatch(of: #/\{(query|selection|clipboard)\}/#) {
        text += rest[..<match.range.lowerBound]
        // In the query or the fragment the text is one value, so it cannot add a field such as `&bcc=`.
        // In the path it may name a path, like owner/repo, but never end the path. In the host it keeps no slash,
        // which would end the host there and put the text's own one in its place.
        let inQuery = text.unicodeScalars.contains { $0 == "?" || $0 == "#" }
        let inPath = text.range(of: "://").map { text[$0.upperBound...].contains("/") } ?? true
        text += LinkText.escaped(values[String(match.output.1)] ?? "", keeping: inQuery || !inPath ? "" : "/")
        rest = rest[match.range.upperBound...]
    }
    return URL(string: text + rest)
}
