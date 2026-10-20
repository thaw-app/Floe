//
//  NoteDesk.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Foundation

/// One Markdown file of the notes folder.
nonisolated struct DeskNote: Identifiable, Hashable, Sendable {
    var url: URL
    var modified: Date

    var id: String {
        url.path
    }

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// The notes of a folder, read and written as the files they are. Floe keeps no copy: the app that owns the
/// folder shows what is written here, and what it writes shows here.
nonisolated enum NoteDesk {
    static let listLimit = 300
    /// A file larger than this is not read into the panel.
    static let largestNote = 1024 * 1024

    /// The folder a notes setting names, with a leading tilde read as home. Nil when the setting is empty or
    /// names no folder, which every view that reads the notes treats as "choose one in Settings".
    static func folder(at path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        return folder
    }

    /// The app that keeps a folder as its own, by the folder it leaves in it. Nil for a plain folder.
    static func owner(of folder: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        var place = folder.standardizedFileURL
        while place.path.count > 1 {
            if FileManager.default.fileExists(atPath: place.appendingPathComponent(".octarine").path) {
                return "Octarine"
            }
            if FileManager.default.fileExists(atPath: place.appendingPathComponent(".obsidian").path) {
                return "Obsidian"
            }
            guard place.path != home.standardizedFileURL.path else { return nil }
            place.deleteLastPathComponent()
        }
        return nil
    }

    /// The Markdown files of the folder and the folders in it, the one changed last first. Hidden ones are left out.
    static func notes(in folder: URL) -> [DeskNote] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [DeskNote] = []
        for case let file as URL in files where file.pathExtension.lowercased() == "md" {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            found.append(DeskNote(url: file, modified: values.contentModificationDate ?? .distantPast))
        }
        return found.min(count: listLimit) { ($0.modified, $1.name) > ($1.modified, $0.name) }
    }

    /// When a file was last changed, asked of the disk each time: a URL remembers the answer it was given before.
    static func modified(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// A note's text and when its file was last changed. Nil for a file that is gone, too large or not text.
    static func read(_ note: URL) -> (text: String, modified: Date?)? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: note.path)
        guard (attributes?[.size] as? Int ?? 0) <= largestNote, let text = try? String(contentsOf: note, encoding: .utf8) else { return nil }
        return (text, attributes?[.modificationDate] as? Date)
    }

    enum Saved: Equatable, Sendable {
        case written(modified: Date?)
        /// The file changed under the editor: it is left as it is, and the editor's text is beside it.
        case keptBeside(URL)
    }

    /// Writes the editor's text, unless the file is no longer the one that was read: then both are kept.
    static func save(_ text: String, to note: URL, readAt modified: Date?, now: Date = Date()) throws -> Saved {
        // A note read without a date is checked by its text, as one whose date moved is.
        if let onDisk = Self.modified(note), onDisk != modified, (try? String(contentsOf: note, encoding: .utf8)) != text {
            let beside = note.deletingLastPathComponent()
                .appendingPathComponent("\(note.deletingPathExtension().lastPathComponent) (Floe \(NoteFiles.stamp("yyyy-MM-dd HH.mm.ss", now))).md")
            try Data(text.utf8).write(to: beside, options: .withoutOverwriting)
            return .keptBeside(beside)
        }
        try Data(text.utf8).write(to: note, options: .atomic)
        return .written(modified: Self.modified(note))
    }

    /// What opens a note in the app that owns the folder: Obsidian's own link, or the file for whatever opens Markdown.
    static func link(to note: URL, owner: String?) -> URL {
        guard owner == "Obsidian" else { return note }
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: note.path)]
        return components.url ?? note
    }

    /// Where the notes are, as the bottom of the view says it: the app first when the folder is one's own.
    static func placeLabel(folder: URL, owner: String?) -> String {
        if let owner {
            return String(localized: "Kept in \(owner): \(folder.lastPathComponent)", bundle: .floe, comment: "Where the notes on screen are stored. The first placeholder is an app, such as Obsidian; the second is a folder's name.")
        }
        return String(localized: "Kept in the folder \(folder.lastPathComponent)", bundle: .floe, comment: "Where the notes on screen are stored. The placeholder is a folder's name.")
    }
}

/// Where the notes' files are read and written: off the main thread, and one at a time, so a save never runs
/// beside a read or another save.
actor NoteFileWorker {
    static let shared = NoteFileWorker()

    func run<T: Sendable>(_ work: @Sendable () throws -> T) rethrows -> T {
        try work()
    }
}
