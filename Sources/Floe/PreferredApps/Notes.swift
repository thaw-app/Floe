//
//  Notes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The app the notes role stands for. Floe keeps no notes of its own: it hands the text to the one already in use.
enum NotesApp: String, Codable, CaseIterable, Identifiable {
    case appleNotes
    case antinote
    /// Any app with a URL scheme, through a template the user writes.
    case custom
    /// A folder of Markdown files, which is what Obsidian, Octarine and others like them keep their notes as.
    case folder

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appleNotes: "Apple Notes"
        case .antinote: "Antinote"
        case .custom: String(localized: "Another App", bundle: .floe)
        case .folder: String(localized: "A Folder of Notes", bundle: .floe)
        }
    }

    /// The app behind the choice, for its icon. Nil for the two that are no one app.
    var bundleID: String? {
        switch self {
        case .appleNotes: "com.apple.Notes"
        case .antinote: "com.chabomakers.Antinote"
        case .custom, .folder: nil
        }
    }

    /// The symbol shown when there is no app icon to show.
    var symbol: String {
        switch self {
        case .appleNotes, .antinote: "note.text"
        case .custom: "link"
        case .folder: "folder"
        }
    }

    /// What the app can be asked to do. Appending needs a notion of the current note, which only Antinote has.
    var actions: [NoteAction] {
        switch self {
        case .antinote: [.new, .append]
        case .folder: [.new, .today]
        case .appleNotes, .custom: [.new]
        }
    }
}

enum NoteAction: String, CaseIterable {
    case new
    case append
    /// Adds a line to the day's note in a folder of notes, so quick thoughts collect in one file.
    case today

    /// The word that starts a note from the search: `note buy milk`.
    var keyword: String {
        switch self {
        case .new: "note"
        case .append, .today: "append"
        }
    }

    var symbol: String {
        switch self {
        case .new: "square.and.pencil"
        case .append, .today: "text.append"
        }
    }

    func title(text: String) -> String {
        switch (self, text.isEmpty) {
        case (.new, true): String(localized: "New Note", bundle: .floe)
        case (.new, false): String(localized: "New Note “\(text)”", bundle: .floe, comment: "The placeholder is the text of the note.")
        case (.append, true): String(localized: "Append to Current Note", bundle: .floe)
        case (.append, false): String(localized: "Append “\(text)” to Current Note", bundle: .floe, comment: "The placeholder is the text added to the note.")
        case (.today, true): String(localized: "Open Today’s Note", bundle: .floe)
        case (.today, false): String(localized: "Append “\(text)” to Today’s Note", bundle: .floe, comment: "The placeholder is the text added to the note.")
        }
    }
}

enum Notes {
    /// The placeholder a custom template puts where the note's text goes.
    static let placeholder = "{text}"

    /// A query that starts with an action's keyword and a space is that action with the rest as its text.
    static func request(in query: String, app: NotesApp) -> (action: NoteAction, text: String)? {
        for action in app.actions {
            let prefix = action.keyword + " "
            guard query.lowercased().hasPrefix(prefix) else { continue }
            let text = query.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (action, text)
        }
        return nil
    }

    /// Text as one value of a URL's query: everything but unreserved characters is escaped, so an
    /// ampersand or an equals sign in a note does not end it.
    static func encoded(_ text: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// The link that hands a note to an app with a URL scheme; nil for Apple Notes, which is scripted,
    /// and for a template that is not a URL.
    static func url(_ action: NoteAction, text: String, app: NotesApp, template: String) -> URL? {
        switch app {
        case .appleNotes, .folder:
            return nil
        case .antinote:
            // Without text there is nothing to make or add: the app is opened instead.
            guard !text.isEmpty else { return URL(string: "antinote://") }
            let path = action == .new ? "createNote" : "appendToCurrent"
            return URL(string: "antinote://x-callback-url/\(path)?content=\(encoded(text))")
        case .custom:
            return URL(string: template.replacingOccurrences(of: placeholder, with: encoded(text)))
        }
    }

    /// The script that makes a note in Apple Notes. A note's body is HTML and its first line is its
    /// title. Without text, Notes comes forward on a new empty note.
    static func appleNotesScript(text: String) -> String {
        guard !text.isEmpty else {
            return """
            tell application "Notes"
                activate
                show (make new note)
            end tell
            """
        }
        let html = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<div>\($0.isEmpty ? "<br>" : String($0))</div>" }
            .joined()
        return "tell application \"Notes\" to make new note with properties {body:\(AppleScript.literal(html))}"
    }

    /// Hands the note over and answers with the line for the HUD, or nil when the app came forward
    /// and shows the result itself. `record` is handed a receipt for what was written into a folder, the one place Floe can account for.
    static func perform(
        _ action: NoteAction,
        text: String,
        app: NotesApp,
        template: String,
        folder: String = "",
        record: (Receipt) -> Void = { _ in /* no receipts kept */ },
        completion: @escaping (String?) -> Void
    ) {
        if app == .folder {
            completion(NoteFiles.perform(action, text: text, folder: folder, record: record))
            return
        }
        guard app == .appleNotes else {
            guard let url = url(action, text: text, app: app, template: template), url.scheme != nil else {
                completion(String(localized: "Set a URL for your notes app in Settings", bundle: .floe))
                return
            }
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                completion(app == .antinote ? String(localized: "Antinote isn't installed", bundle: .floe, comment: "Antinote is the name of an app.") : String(localized: "No app opens that URL", bundle: .floe))
                return
            }
            NSWorkspace.shared.openWithoutWaiting(url)
            completion(nil)
            return
        }
        let source = appleNotesScript(text: text)
        AppleScript.execute(source, qos: .userInitiated) { execution in
            switch execution.errorNumber {
            case nil: completion(text.isEmpty ? nil : String(localized: "Saved to Notes", bundle: .floe, comment: "Notes is Apple's notes app."))
            case AppleScript.refusedErrorNumber: SystemCommand.askForAutomation(toControl: "Notes")
            default: completion(String(localized: "Couldn't save the note in Notes", bundle: .floe, comment: "Notes is Apple's notes app."))
            }
        }
    }
}

/// Notes kept as Markdown files in a folder the user chose. The apps that read such a folder show them as their own.
enum NoteFiles {
    /// A new note's file name: its first line, without what a file name cannot hold. Numbered when taken, and
    /// the date and time when the first line leaves nothing.
    static func fileName(for text: String, now: Date, taken: (String) -> Bool) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = firstLine.map { "/:\\".contains($0) ? " " : String($0) }.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .#*-"))
        let base = cleaned.isEmpty ? stamp("yyyy-MM-dd HH.mm", now) : String(cleaned.prefix(60))
        var name = "\(base).md"
        var number = 2
        while taken(name) {
            name = "\(base) \(number).md"
            number += 1
        }
        return name
    }

    /// A date written out by a fixed pattern, in the given time zone: the user's own unless said otherwise.
    static func stamp(_ pattern: String, _ date: Date, in zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// The day's note: one file a day, named by its date where the user is.
    static func todayName(now: Date, in zone: TimeZone = .current) -> String {
        stamp("yyyy-MM-dd", now, in: zone) + ".md"
    }

    /// What the day's note holds once a line is added: the line by itself in a new file, and on a line of its own after what is there.
    static func appended(_ text: String, to existing: String) -> String {
        guard !existing.isEmpty else { return text + "\n" }
        return existing + (existing.hasSuffix("\n") ? "" : "\n") + text + "\n"
    }

    /// Writes a new note. Never over a file that is there.
    @discardableResult
    static func write(_ text: String, in folder: URL, now: Date = Date()) throws -> URL {
        let file = folder.appendingPathComponent(fileName(for: text, now: now) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) })
        try Data((text + "\n").utf8).write(to: file, options: .withoutOverwriting)
        return file
    }

    /// Where the app that owns a folder keeps the day's note, so a line Floe adds lands in the note the app
    /// shows for today. Octarine keeps it in Daily; Obsidian in the vault, or in the folder its settings name.
    static func dayFolder(in folder: URL) -> URL {
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.appendingPathComponent(".octarine").path) {
            return folder.appendingPathComponent("Daily", isDirectory: true)
        }
        let settings = folder.appendingPathComponent(".obsidian/daily-notes.json")
        if let data = try? Data(contentsOf: settings), let chosen = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["folder"] as? String,
           !chosen.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).isEmpty
        {
            return folder.appendingPathComponent(chosen, isDirectory: true)
        }
        return folder
    }

    /// The day's note in a folder: the app's own place for it, under today's date where the user is. Octarine
    /// was seen to date a note by the day in UTC: when only that one is there, it is the note the app shows for today.
    static func dayFile(in folder: URL, now: Date) -> URL {
        let place = dayFolder(in: folder)
        let local = place.appendingPathComponent(todayName(now: now))
        guard let utc = TimeZone(identifier: "UTC") else { return local }
        let elsewhere = place.appendingPathComponent(todayName(now: now, in: utc))
        let manager = FileManager.default
        return !manager.fileExists(atPath: local.path) && manager.fileExists(atPath: elsewhere.path) ? elsewhere : local
    }

    /// Adds a line to the day's note, making the file when it is the day's first.
    @discardableResult
    static func append(_ text: String, in folder: URL, now: Date = Date()) throws -> URL {
        let file = dayFile(in: folder, now: now)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: String
        do {
            existing = try String(contentsOf: file, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            existing = ""
        }
        try Data(appended(text, to: existing).utf8).write(to: file, options: .atomic)
        return file
    }

    /// Does what a note row asks of the folder and answers with the line for the HUD. Without text the folder,
    /// or the day's note, is opened to write in. `record` is handed the receipt of a file written or added to.
    static func perform(
        _ action: NoteAction,
        text: String,
        folder path: String,
        now: Date = Date(),
        open: (URL) -> Void = { NSWorkspace.shared.open($0) },
        record: (Receipt) -> Void = { _ in /* no receipts kept */ }
    ) -> String? {
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isFolder: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            return String(localized: "Choose a folder for your notes in Settings", bundle: .floe)
        }
        do {
            switch (action, text.isEmpty) {
            case (.today, true):
                let today = dayFile(in: folder, now: now)
                open(FileManager.default.fileExists(atPath: today.path) ? today : folder)
                return nil
            case (_, true):
                open(folder)
                return nil
            case (.today, false):
                try record(.noteLine(text, in: append(text, in: folder, now: now), now: now))
                return String(localized: "Added to today’s note", bundle: .floe)
            case (_, false):
                let file = try write(text, in: folder, now: now)
                record(.note(file, now: now))
                return String(localized: "Saved \(file.deletingPathExtension().lastPathComponent)", bundle: .floe, comment: "Shown briefly after saving. The placeholder is the name the user gave.")
            }
        } catch {
            return String(localized: "Couldn’t save the note: \(error.localizedDescription)", bundle: .floe, comment: "The placeholder is the reason the system gave.")
        }
    }
}

/// The folders of notes that apps on this Mac already keep, offered in Settings so the user need not find them.
enum KnownNoteFolders {
    struct Folder: Identifiable, Hashable {
        let app: String
        let path: String

        var id: String {
            path
        }

        /// "Obsidian: Documents", by the app and the folder's name.
        var title: String {
            "\(app): \((path as NSString).lastPathComponent)"
        }
    }

    /// Obsidian's vaults, from the list it keeps of them.
    static func obsidianVaults(in data: Data?) -> [String] {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = root["vaults"] as? [String: [String: Any]] else { return [] }
        return vaults.values.compactMap { $0["path"] as? String }.sorted()
    }

    /// Octarine's workspaces, from the table it keeps of them. Read with the system's sqlite3, without opening the app.
    static func octarineWorkspaces(database: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        let sqlite = Process()
        sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqlite.arguments = ["-readonly", database.path, "select path from workspaces;"]
        let pipe = Pipe()
        sqlite.standardOutput = pipe
        sqlite.standardError = FileHandle.nullDevice
        guard (try? sqlite.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        sqlite.waitUntilExit()
        return (String(bytes: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline).map(String.init).filter { $0.hasPrefix("/") }.sorted()
    }

    /// Every folder an app keeps notes in that is still there.
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Folder] {
        let support = home.appendingPathComponent("Library/Application Support")
        let obsidian = obsidianVaults(in: try? Data(contentsOf: support.appendingPathComponent("obsidian/obsidian.json"))).map { Folder(app: "Obsidian", path: $0) }
        let octarine = octarineWorkspaces(database: support.appendingPathComponent("Octarine/octarine.sqlite")).map { Folder(app: "Octarine", path: $0) }
        return (obsidian + octarine).filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
