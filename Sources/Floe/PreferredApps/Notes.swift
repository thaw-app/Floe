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
        case .folder: [.new, .today, .task, .log]
        case .appleNotes, .custom: [.new]
        }
    }
}

enum NoteAction: String, CaseIterable {
    case new
    case append
    /// Adds a line to the day's note in a folder of notes, so quick thoughts collect in one file.
    case today
    /// Adds a line to the day's note as a task: Obsidian and Octarine draw `- [ ]` as a checkbox.
    case task
    /// Adds a line to the day's note with the time in front, as a journal keeps them.
    case log

    /// The word that starts a note from the search: `note buy milk`.
    var keyword: String {
        switch self {
        case .new: "note"
        case .append, .today: "append"
        case .task: "todo"
        case .log: "log"
        }
    }

    var symbol: String {
        switch self {
        case .new: "square.and.pencil"
        case .append, .today: "text.append"
        case .task: "checklist"
        case .log: "clock"
        }
    }

    /// Whether the action writes into the day's note of a folder.
    var addsToDaysNote: Bool {
        self == .today || self == .task || self == .log
    }

    /// Whether the action has a row of its own with nothing typed. A task and a journal line share the day's note's.
    var standsAlone: Bool {
        self != .task && self != .log
    }

    func title(text: String) -> String {
        switch (self, text.isEmpty) {
        case (.new, true): String(localized: "New Note", bundle: .floe)
        case (.new, false): String(localized: "New Note “\(text)”", bundle: .floe, comment: "The placeholder is the text of the note.")
        case (.append, true): String(localized: "Append to Current Note", bundle: .floe)
        case (.append, false): String(localized: "Append “\(text)” to Current Note", bundle: .floe, comment: "The placeholder is the text added to the note.")
        case (.today, true), (.task, true), (.log, true): String(localized: "Open Today’s Note", bundle: .floe)
        case (.today, false): String(localized: "Append “\(text)” to Today’s Note", bundle: .floe, comment: "The placeholder is the text added to the note.")
        case (.task, false): String(localized: "Add Task “\(text)” to Today’s Note", bundle: .floe, comment: "The placeholder is what the task is, such as renew passport.")
        case (.log, false): String(localized: "Log “\(text)” in Today’s Note", bundle: .floe, comment: "Log is a verb: write a line with the time in a journal. The placeholder is the line.")
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

    /// Whether a query is one of the day's note's words and nothing else, with an app that keeps one. `todo` and `log` alone stay ordinary searches, so Todoist and Logseq are still found.
    static func opensDaysNote(_ query: String, app: NotesApp) -> Bool {
        let word = query.trimmingCharacters(in: .whitespaces).lowercased()
        return app.actions.contains { $0.addsToDaysNote && $0.standsAlone && $0.keyword == word }
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
            return URL(string: "antinote://x-callback-url/\(path)?content=\(LinkText.escaped(text))")
        case .custom:
            return URL(string: template.replacingOccurrences(of: placeholder, with: LinkText.escaped(text)))
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

    /// The line an action adds to the day's note: the text, a task with an empty checkbox, or the local time and the text.
    static func line(_ action: NoteAction, text: String, now: Date, in zone: TimeZone = .current) -> String {
        switch action {
        case .task: "- [ ] \(text)"
        case .log: "- \(stamp("HH:mm", now, in: zone)) \(text)"
        default: text
        }
    }

    /// Writes a new note. Never over a file that is there.
    @discardableResult
    static func write(_ text: String, in folder: URL, now: Date = Date()) throws -> URL {
        let file = folder.appendingPathComponent(fileName(for: text, now: now) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) })
        try Data((text + "\n").utf8).write(to: file, options: .withoutOverwriting)
        return file
    }

    /// What a vault's settings say about daily notes: `folder` and `format`. Empty for a folder that is not Obsidian's, or is Octarine's.
    static func obsidianDailyNotes(in folder: URL) -> [String: Any] {
        guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent(".octarine").path),
              let data = try? Data(contentsOf: folder.appendingPathComponent(".obsidian/daily-notes.json")) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Where the app that owns a folder keeps the day's note, so a line Floe adds lands in the note the app
    /// shows for today. Octarine keeps it in Daily; Obsidian in the vault, or in the folder its settings name.
    static func dayFolder(in folder: URL) -> URL {
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".octarine").path) {
            return folder.appendingPathComponent("Daily", isDirectory: true)
        }
        if let chosen = obsidianDailyNotes(in: folder)["folder"] as? String, !chosen.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).isEmpty {
            return folder.appendingPathComponent(chosen, isDirectory: true)
        }
        return folder
    }

    /// The day's note as a pattern names it, subfolders and all. A pattern Floe cannot read gives the standard name,
    /// which is where Obsidian looks when it has none.
    static func dayName(format: String?, now: Date, in zone: TimeZone = .current) -> String {
        let named = format.flatMap { $0.isEmpty ? nil : MomentPattern.text($0, for: now, in: zone) }
        return (named ?? stamp("yyyy-MM-dd", now, in: zone)) + ".md"
    }

    /// The day's note in a folder: the app's own place and name for it, for today where the user is. Octarine
    /// was seen to date a note by the day in UTC: when only that one is there, it is the note the app shows for today.
    static func dayFile(in folder: URL, now: Date, timeZone: TimeZone = .current) -> URL {
        let place = dayFolder(in: folder)
        let format = obsidianDailyNotes(in: folder)["format"] as? String
        let local = place.appendingPathComponent(dayName(format: format, now: now, in: timeZone))
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(".octarine").path),
              let utc = TimeZone(identifier: "UTC") else { return local }
        let elsewhere = place.appendingPathComponent(dayName(format: format, now: now, in: utc))
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
            switch (action.addsToDaysNote, text.isEmpty) {
            case (true, true):
                let today = dayFile(in: folder, now: now)
                open(FileManager.default.fileExists(atPath: today.path) ? today : folder)
                return nil
            case (false, true):
                open(folder)
                return nil
            case (true, false):
                let line = line(action, text: text, now: now)
                try record(.noteLine(line, in: append(line, in: folder, now: now), now: now))
                return String(localized: "Added to today’s note", bundle: .floe)
            case (false, false):
                let file = try write(text, in: folder, now: now)
                record(.note(file, now: now))
                return String(localized: "Saved \(file.deletingPathExtension().lastPathComponent)", bundle: .floe, comment: "Shown briefly after saving. The placeholder is the name the user gave.")
            }
        } catch {
            return String(localized: "Couldn’t save the note: \(error.localizedDescription)", bundle: .floe, comment: "The placeholder is the reason the system gave.")
        }
    }
}
