//
//  Bookmarks.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A bookmark saved in a browser, read from the file the browser keeps them in.
nonisolated struct WebBookmark: Hashable, Sendable {
    let title: String
    let url: URL
    let browser: String

    /// Beside the title: the site, or the browser when the address has none.
    var label: String {
        url.host(percentEncoded: false) ?? browser
    }
}

/// `bookmarks invoice`: the bookmarks of the Chromium browsers on this Mac. Each keeps them as a JSON file
/// in its profile folder, which Floe reads only when the word is typed. Safari's are behind Full Disk Access.
nonisolated enum Bookmarks {
    static let keyword = "bookmarks"
    /// How many rows the scope shows; a browser can hold thousands.
    static let rowLimit = 50

    /// Each browser's name and its folder under Application Support.
    static let browsers: [(name: String, folder: String)] = [
        ("Chrome", "Google/Chrome"), ("Brave", "BraveSoftware/Brave-Browser"), ("Edge", "Microsoft Edge"), ("Arc", "Arc/User Data"),
        ("Vivaldi", "Vivaldi"), ("Dia", "Dia/User Data"), ("Helium", "net.imput.helium"), ("Chromium", "Chromium"),
    ]

    /// Every bookmark of every profile of every browser found under `support`.
    static func read(support: URL = .applicationSupportDirectory) -> [WebBookmark] {
        browsers.flatMap { browser -> [WebBookmark] in
            let root = support.appendingPathComponent(browser.folder)
            let profiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return profiles
                .filter { $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { try? Data(contentsOf: $0.appendingPathComponent("Bookmarks")) }
                .flatMap { parse($0, browser: browser.name) }
        }
        .uniqued(on: \.url)
    }

    private struct File: Decodable {
        let roots: [String: Node]
    }

    private struct Node: Decodable {
        let type: String?
        let name: String?
        let url: String?
        let children: [Node]?

        /// The links under this node, folders walked through.
        func links(browser: String) -> [WebBookmark] {
            if type == "url", let url = url.flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true {
                return [WebBookmark(title: name.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString, url: url, browser: browser)]
            }
            return (children ?? []).flatMap { $0.links(browser: browser) }
        }
    }

    /// The links in one browser's file. A file that is not what a Chromium browser writes gives none.
    static func parse(_ data: Data, browser: String) -> [WebBookmark] {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.roots.keys.sorted().flatMap { file.roots[$0]?.links(browser: browser) ?? [] }
    }
}

/// The scope reads the files off the main thread each time it is asked, so a bookmark added a moment ago is there.
struct BookmarkSearchScope: SearchScope {
    let keyword = Bookmarks.keyword
    let title = String(localized: "Bookmarks", bundle: .floe)
    let emptyTitle = String(localized: "No bookmark matches", bundle: .floe)
    var read: @Sendable () -> [WebBookmark] = { Bookmarks.read() }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        .once { [read] in Self.ranked(read(), query: text).prefix(Bookmarks.rowLimit).map(RootItem.bookmark) }
    }

    /// Bookmarks whose title or site matches, best first.
    static nonisolated func ranked(_ bookmarks: [WebBookmark], query: String) -> [WebBookmark] {
        bookmarks.ranked { Ranking.menuBarScore(query: query, name: $0.title, owner: $0.label) }
    }
}
