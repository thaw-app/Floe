//
//  QuicklinkImport.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import Foundation

/// Turns Raycast's quicklinks into Floe's. Only decides: the caller adds what it returns.
enum QuicklinkImport {
    /// What the import needs from the Mac.
    struct Apps {
        /// The home folder, for a link to `~/…`.
        var home: URL
        /// The app a Raycast link names, by its name or path, when it is installed.
        var app: (String) -> AppChoice?
    }

    struct Plan {
        var added: [Quicklink] = []
        var skipped: [Skipped] = []
        /// The links whose app is not on this Mac. They come in all the same, to open as any link of their kind.
        var withoutApp: [String] = []
    }

    struct Skipped: Equatable {
        var name: String
        var reason: Reason
    }

    enum Reason: Error, Equatable {
        case alreadyThere
        /// Floe fills one piece of typed text, and the link asks for more.
        case severalArguments
        /// A Raycast placeholder Floe has no value for, such as `date`.
        case placeholder(String)
        /// Neither an address with a scheme nor a path.
        case notALink
    }

    static func plan(_ links: [RaycastQuicklink], existing: [Quicklink], apps: Apps) -> Plan {
        var plan = Plan()
        var keywords = Set(existing.map { $0.keyword.lowercased() })
        var seen = Set(existing.map { [$0.name, $0.url] })
        for link in links {
            let url: String
            switch floeURL(link.link, home: apps.home) {
            case let .success(converted):
                url = converted
            case let .failure(reason):
                plan.skipped.append(Skipped(name: link.name, reason: reason))
                continue
            }
            guard seen.insert([link.name, url]).inserted else {
                plan.skipped.append(Skipped(name: link.name, reason: .alreadyThere))
                continue
            }
            let keyword = unused(keyword(for: link.name), in: keywords)
            keywords.insert(keyword)
            let app = link.openWith.flatMap(apps.app)
            if link.openWith != nil, app == nil {
                plan.withoutApp.append(link.name)
            }
            plan.added.append(Quicklink(name: link.name, keyword: keyword, url: url, symbol: symbol(for: link.iconName, url: url), openWith: app))
        }
        return plan
    }

    /// The keyword itself while it is free, else with the first number from 2 that makes it so.
    private static func unused(_ keyword: String, in taken: Set<String>) -> String {
        guard taken.contains(keyword) else { return keyword }
        return (2...).lazy.map { "\(keyword)\($0)" }.first { !taken.contains($0) } ?? keyword
    }

    private static let placeholderPattern = #/\{([A-Za-z][\w-]*)([^}]*)\}/#

    /// Why Floe can't fill a placeholder, or nil when it can. An argument may have a name and a default; the
    /// selection and the clipboard take no options, such as an earlier copy's `offset`.
    private static func problem(with word: String, options: String, modifiers: [String]) -> Reason? {
        switch word {
        case "argument", "query":
            modifiers.isEmpty ? nil : .placeholder(([word] + modifiers).joined(separator: " | "))
        case "selection", "clipboard":
            options.isEmpty && modifiers.isEmpty ? nil : .placeholder(([options.isEmpty ? word : "\(word) \(options)"] + modifiers).joined(separator: " | "))
        default:
            .placeholder(word)
        }
    }

    /// Raycast's `{argument …}` and `{query}` become Floe's `{query}`: one name used twice is one argument, each unnamed
    /// one its own. `{selection}` and `{clipboard}` stay, read when the link opens.
    private static func floeURL(_ link: String, home: URL) -> Result<String, Reason> {
        var arguments = Set<String>()
        for match in link.matches(of: placeholderPattern) {
            let word = match.output.1.lowercased()
            // Floe encodes the text and changes nothing else in it, as Raycast's percent-encode does.
            let parts = match.output.2.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let modifiers = parts.dropFirst().filter { $0 != "percent-encode" }
            let options = parts.first ?? ""
            if let problem = problem(with: word, options: options, modifiers: Array(modifiers)) {
                return .failure(problem)
            }
            if word == "argument" || word == "query" {
                let name = options.firstMatch(of: #/name\s*=\s*"([^"]*)"/#).map { String($0.output.1) }
                arguments.insert(name ?? UUID().uuidString)
            }
        }
        guard arguments.count <= 1 else { return .failure(.severalArguments) }
        var url = link.replacing(placeholderPattern) { match in
            let word = match.output.1.lowercased()
            return word == "selection" || word == "clipboard" ? "{\(word)}" : "{query}"
        }
        if url.hasPrefix("~/") || url == "~" {
            url = home.appending(path: String(url.dropFirst(2)), directoryHint: .notDirectory).absoluteString
        } else if url.hasPrefix("/") {
            url = URL(filePath: url, directoryHint: .notDirectory).absoluteString
        }
        // A file URL escapes the braces, and Floe fills its placeholders only as they are written.
        for word in ["query", "selection", "clipboard"] {
            url = url.replacing("%7B\(word)%7D", with: "{\(word)}")
        }
        guard let scheme = URL(string: url)?.scheme, !scheme.isEmpty else { return .failure(.notALink) }
        return .success(url)
    }

    /// Raycast's icons that have a symbol to match, by their name without the size.
    private static let symbols = [
        "folder": "folder", "book": "book", "globe": "globe", "magnifying-glass": "magnifyingglass",
        "terminal": "terminal", "code": "chevron.left.forwardslash.chevron.right", "envelope": "envelope",
        "calendar": "calendar", "star": "star", "house": "house", "person": "person", "document": "doc",
        "link": "link", "bookmark": "bookmark", "map": "map", "music": "music.note", "video": "play.rectangle",
    ]

    private static func symbol(for iconName: String?, url: String) -> String {
        let name = iconName?.replacing(#/-\d+$/#, with: "")
        return name.flatMap { symbols[$0] } ?? (url.contains("{query}") ? "magnifyingglass" : "link")
    }

    /// The first letter of each word, or the one word whole; `link` for a name with neither letters nor digits.
    private static func keyword(for name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.count > 1 ? String(words.compactMap(\.first)) : words.first.map(String.init) ?? "link"
    }
}
