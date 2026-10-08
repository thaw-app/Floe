//
//  Checkpoints.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What the user was doing, saved to come back to: the files and folders selected in Finder, the tabs of the
/// browser window in front, and a note of the next step. Not which apps were open.
nonisolated struct Checkpoint: Codable, Identifiable, Hashable, Sendable {
    enum ItemKind: String, Codable, Sendable {
        case file, link
    }

    struct Item: Codable, Hashable, Sendable {
        var kind: ItemKind
        /// A path, or a web address.
        var value: String
        var title: String
    }

    var id = UUID()
    var name: String
    var note: String
    var items: [Item]
    var saved: Date

    static let keyword = "pause"
    /// A window with a hundred tabs is not a task: the first of them are kept.
    static let tabLimit = 30

    /// `pause website redesign: fix the nav next` asks for a checkpoint by that name with that note.
    static func request(in query: String) -> (name: String, note: String)? {
        let words = query.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard words.count == 2, words[0].lowercased() == keyword else { return nil }
        let parts = words[1].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let note = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        return name.isEmpty ? nil : (name, note)
    }

    /// "3 files and 5 tabs", and what there is when one of the two is none.
    var summary: String {
        let files = items.count { $0.kind == .file }
        let tabs = items.count { $0.kind == .link }
        let fileText = String(localized: "\(files) files", bundle: .floe, comment: "A count of files and folders in a checkpoint.")
        let tabText = String(localized: "\(tabs) tabs", bundle: .floe, comment: "A count of browser tabs in a checkpoint.")
        switch (files > 0, tabs > 0) {
        case (true, true): return String(localized: "\(fileText) and \(tabText)", bundle: .floe, comment: "Two counts joined, such as 3 files and 5 tabs.")
        case (true, false): return fileText
        case (false, true): return tabText
        case (false, false): return String(localized: "a note", bundle: .floe, comment: "What a checkpoint holds when it has no files and no tabs.")
        }
    }

    /// The files and folders that are no longer where they were.
    func missing(exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Item] {
        items.filter { $0.kind == .file && !exists($0.value) }
    }

    /// Everything the checkpoint holds, one line each, with what is missing marked.
    func details(exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        var lines = [name, saved.formatted(date: .abbreviated, time: .shortened)]
        if !note.isEmpty {
            lines += ["", note]
        }
        let gone = Set(missing(exists: exists))
        lines.append("")
        lines += items.map { item in
            let place = item.kind == .file ? (item.value as NSString).abbreviatingWithTildeInPath : item.value
            return gone.contains(item) ? String(localized: "Missing: \(place)", bundle: .floe, comment: "A file a checkpoint held that is gone. The placeholder is its path.") : place
        }
        return lines.joined(separator: "\n")
    }

    /// The tabs of the window in front in each browser: the first window a browser lists is the one in front.
    static func frontWindowTabs(_ tabs: [BrowserTab]) -> [BrowserTab] {
        var front: [String: String] = [:]
        return Array(tabs.filter { tab in
            let window = front[tab.browser.bundleID] ?? tab.window
            front[tab.browser.bundleID] = window
            return tab.window == window
        }.prefix(tabLimit))
    }

    static func items(files: [URL], tabs: [BrowserTab]) -> [Item] {
        files.map { Item(kind: .file, value: $0.path, title: $0.lastPathComponent) }
            + frontWindowTabs(tabs).filter { !$0.url.isEmpty }.map { Item(kind: .link, value: $0.url, title: $0.title) }
    }
}

/// The checkpoints, newest first, in a file.
final nonisolated class CheckpointStore: Sendable {
    static let shared = CheckpointStore()

    private let file: URL

    init(file: URL = Paths.support.appendingPathComponent("Checkpoints.json")) {
        self.file = file
    }

    var all: [Checkpoint] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Checkpoint].self, from: $0) } ?? []
    }

    /// Saves a checkpoint. One of the same name is replaced: pausing a task again is the newer state of it.
    func save(_ checkpoint: Checkpoint) {
        write([checkpoint] + all.filter { $0.name.caseInsensitiveCompare(checkpoint.name) != .orderedSame })
    }

    func delete(_ id: UUID) {
        write(all.filter { $0.id != id })
    }

    private func write(_ checkpoints: [Checkpoint]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(checkpoints).write(to: file, options: .atomic)
    }
}

/// `pause` and a name leads the results with the row that saves a checkpoint. Saved ones are found by name.
struct CheckpointSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        let saved = context.checkpoints.map(RootItem.checkpoint)
        guard let request = Checkpoint.request(in: context.trimmed) else { return SearchContribution(searchOnly: saved) }
        let draft = RootResult(item: .checkpointDraft(name: request.name, note: request.note), section: nil)
        return SearchContribution(searchOnly: saved, pinned: [draft])
    }
}
