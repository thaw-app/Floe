//
//  ClipboardSearchScope.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `clipboard meeting`: the saved copies that match, as the clipboard history lists them.
struct ClipboardSearchScope: SearchScope {
    /// The history is long; the scope shows the first screens of it.
    static let limit = 50

    let keyword = "clipboard"
    let title = String(localized: "Clipboard History", bundle: .floe)
    let emptyTitle = String(localized: "No clipboard entries match", bundle: .floe)
    /// The history is read through this, so a test can stand in for the user's own.
    var entries: () -> [ClipboardEntry] = { [] }

    func results(for text: String, context _: SearchContext) -> [RootItem] {
        Self.matching(entries(), query: text).prefix(Self.limit).map(RootItem.clipboardEntry)
    }

    /// Entries whose text, files or source app contain every word of the query, pins first, then newest first.
    static func matching(_ entries: [ClipboardEntry], query: String) -> [ClipboardEntry] {
        let tokens = query.lowercased().split(separator: " ")
        let matching = tokens.isEmpty ? entries : entries.filter { entry in
            let haystack = "\(entry.title) \(entry.text ?? "") \((entry.filePaths ?? []).joined(separator: " ")) \(entry.sourceApp ?? "")".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
        return matching.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned
            }
            return lhs.date > rhs.date
        }
    }
}

nonisolated extension ClipboardEntry.Kind {
    var symbol: String {
        switch self {
        case .text: "doc.text"
        case .link: "link"
        case .image: "photo"
        case .file: "folder"
        }
    }
}
