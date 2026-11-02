//
//  Checkpoints.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import UniformTypeIdentifiers

/// What the user was doing, saved to come back to: the files and folders selected in Finder, the tabs of the
/// browser window in front, a note of the next step, and the apps that were open when the user asks for them.
nonisolated struct Checkpoint: Codable, Identifiable, Hashable, Sendable {
    enum ItemKind: String, Codable, Sendable {
        case file, link, app
    }

    struct Item: Codable, Hashable, Sendable {
        var kind: ItemKind
        /// A path of a file, a folder or an app, or a web address.
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

    /// Whether resuming brings apps back along with the files and tabs.
    var holdsApps: Bool {
        items.contains { $0.kind == .app }
    }

    /// "3 files and 5 tabs", leaving out what there is none of.
    var summary: String {
        let files = items.count { $0.kind == .file }
        let tabs = items.count { $0.kind == .link }
        let apps = items.count { $0.kind == .app }
        var counts: [String] = []
        if files > 0 {
            counts.append(String(localized: "\(files) files", bundle: .floe, comment: "A count of files and folders in a checkpoint."))
        }
        if tabs > 0 {
            counts.append(String(localized: "\(tabs) tabs", bundle: .floe, comment: "A count of browser tabs in a checkpoint."))
        }
        if apps > 0 {
            counts.append(String(localized: "\(apps) apps", bundle: .floe, comment: "A count of open apps in a checkpoint."))
        }
        return counts.isEmpty
            ? String(localized: "a note", bundle: .floe, comment: "What a checkpoint holds when it has no files and no tabs.")
            : counts.formatted(.list(type: .and))
    }

    /// The files, folders and apps that are no longer where they were.
    func missing(exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Item] {
        items.filter { $0.kind != .link && !exists($0.value) }
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
            let place = item.kind == .link ? item.value : (item.value as NSString).abbreviatingWithTildeInPath
            return gone.contains(item) ? String(localized: "Missing: \(place)", bundle: .floe, comment: "A file a checkpoint held that is gone. The placeholder is its path.") : place
        }
        return lines.joined(separator: "\n")
    }

    /// Whether a file is one an editor is for: plain text or source code, by what the system says it is.
    static func isText(_ file: URL) -> Bool {
        let type = (try? file.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: file.pathExtension)
        return type.map { $0.conforms(to: .text) || $0.conforms(to: .sourceCode) } ?? false
    }

    /// What the chosen editor is handed when a checkpoint is resumed: a text or code file. Nil for a folder, which is
    /// Finder's, for any other file, which is its own app's, and while no editor is chosen.
    static func editorHandoff(for item: URL, editor: ResolvedApp?, isFolder: (URL) -> Bool = PreferredApps.isFolder, isText: (URL) -> Bool = isText) -> Handoff? {
        guard let editor, !isFolder(item), isText(item) else { return nil }
        return Handoff(urls: [item], application: editor.url)
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

    /// The tabs of a browser that is starting, once it has restored them: two reads in a row that agree, or the last read
    /// when it never settles, as with a browser Floe may not ask.
    static func settledTabs(
        reads: Int = 8,
        read: @Sendable () async -> [BrowserTab],
        pause: @Sendable () async -> Void
    ) async -> [BrowserTab] {
        var last = await read()
        for _ in 1 ..< reads {
            await pause()
            let next = await read()
            if !next.isEmpty, next.map(\.url) == last.map(\.url) {
                return next
            }
            last = next
        }
        return last
    }

    static func items(files: [URL], tabs: [BrowserTab], apps: [Item] = []) -> [Item] {
        files.map { Item(kind: .file, value: $0.path, title: $0.lastPathComponent) }
            + frontWindowTabs(tabs).filter { !$0.url.isEmpty }.map { Item(kind: .link, value: $0.url, title: $0.title) }
            + apps
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
        JSONFile.read([Checkpoint].self, from: file) ?? []
    }

    /// Saves a checkpoint. One of the same name is replaced: pausing a task again is the newer state of it.
    func save(_ checkpoint: Checkpoint) {
        write([checkpoint] + all.filter { $0.name.caseInsensitiveCompare(checkpoint.name) != .orderedSame })
    }

    func delete(_ id: UUID) {
        write(all.filter { $0.id != id })
    }

    private func write(_ checkpoints: [Checkpoint]) {
        JSONFile.write(checkpoints, to: file)
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
