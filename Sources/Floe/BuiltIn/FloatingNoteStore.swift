//
//  FloatingNoteStore.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// One note the floating note can show, as its store knows it.
nonisolated struct FloatingNote: Identifiable, Hashable, Sendable {
    /// What the store finds the note by: a file's path, or the id Apple Notes gives it.
    var id: String
    var name: String
    /// When the note was last changed as it was read. Only a folder can say.
    var modified: Date?
}

/// The app the scratch note goes to, and its name for the button that sends it.
nonisolated struct NoteRecipient: Equatable, Sendable {
    var app: NotesApp
    var name: String
}

/// Why the floating note could not reach where its notes are. Each case says what to do about it.
nonisolated enum FloatingNoteError: Error, Equatable {
    case noFolder
    /// The file is too large to edit here, or is not text.
    case unreadable
    /// macOS did not let Floe control Notes.
    case refused
    case failed(String)

    /// What the window says. A failure names what was being done when it came.
    func message(saving: Bool) -> String {
        switch self {
        case .noFolder: String(localized: "Choose a folder for your notes in Settings", bundle: .floe)
        case .unreadable: String(localized: "This note is too large to show here, or is not text.", bundle: .floe)
        case .refused: String(localized: "Floe needs permission to control Notes. Your text stays here until it can save.", bundle: .floe, comment: "Notes is Apple's notes app.")
        case let .failed(reason) where saving: String(localized: "Couldn’t save the note: \(reason)", bundle: .floe, comment: "The placeholder is the reason the system gave.")
        case let .failed(reason): String(localized: "Couldn’t open the notes: \(reason)", bundle: .floe, comment: "The placeholder is the reason the system gave.")
        }
    }
}

/// Where the floating note's text lives: a folder of Markdown files, Floe's folder in Apple Notes, or the
/// scratch note for an app that cannot be read back. The window does not know which.
protocol FloatingNoteStore: AnyObject {
    /// Where the notes are, as the bottom of the window says it.
    var place: String { get }
    /// The app the scratch note is sent to. Nil for a store that keeps the notes itself and lists them.
    var sendsTo: NoteRecipient? { get }
    /// The notes to switch between, the one changed last first where the store can tell.
    func notes() async throws -> [FloatingNote]
    func read(_ note: FloatingNote) async throws -> (note: FloatingNote, text: String)
    /// Saves the text and answers with the note as it stands now: another one when the store kept the text
    /// beside a note that changed elsewhere.
    func save(_ text: String, to note: FloatingNote) async throws -> FloatingNote
    /// A new note, named by `name` when it is not empty.
    func makeNote(named name: String) async throws -> FloatingNote
    /// The note's text when something else changed it since it was read, and nil when nothing did.
    func changes(to note: FloatingNote) async -> (note: FloatingNote, text: String)?
}

/// Picks the store for the notes app the user chose.
enum FloatingNoteStores {
    static func store(for app: NotesApp, folder: String, template: String, record: @escaping (Receipt) -> Void) -> any FloatingNoteStore {
        switch app {
        case .folder: FolderNoteStore(folder: NoteDesk.folder(at: folder), record: record)
        case .appleNotes: AppleNotesStore()
        case .antinote, .custom: ScratchNoteStore(app: app, appName: appName(for: app, template: template))
        }
    }

    /// The app a custom template opens, by its name, so the button says where the text goes. The choice's
    /// own title when no app opens the template.
    static func appName(for app: NotesApp, template: String) -> String {
        guard app == .custom,
              let url = Notes.url(.new, text: "", app: app, template: template), url.scheme != nil,
              let opener = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { return app.title }
        return opener.deletingPathExtension().lastPathComponent
    }
}

/// The notes of the folder the Note Desk reads, read and written as the files they are.
final class FolderNoteStore: FloatingNoteStore {
    let folder: URL?
    private let record: (Receipt) -> Void
    private let list: @Sendable (URL) -> [DeskNote]

    init(
        folder: URL?,
        record: @escaping (Receipt) -> Void = { _ in
            // No receipts kept.
        },
        list: @escaping @Sendable (URL) -> [DeskNote] = NoteDesk.notes
    ) {
        self.folder = folder
        self.record = record
        self.list = list
    }

    var place: String {
        guard let folder else { return "" }
        return NoteDesk.placeLabel(folder: folder, owner: NoteDesk.owner(of: folder))
    }

    var sendsTo: NoteRecipient? {
        nil
    }

    /// Read off the main thread: a large vault takes a while to walk.
    func notes() async throws -> [FloatingNote] {
        guard let folder else { throw FloatingNoteError.noFolder }
        let list = list
        return await Task.detached { list(folder) }.value
            .map { FloatingNote(id: $0.url.path, name: $0.name, modified: $0.modified) }
    }

    func read(_ note: FloatingNote) async throws -> (note: FloatingNote, text: String) {
        let file = URL(fileURLWithPath: note.id)
        guard let read = NoteDesk.read(file) else { throw FloatingNoteError.unreadable }
        return (FloatingNote(id: note.id, name: note.name, modified: read.modified), read.text)
    }

    func save(_ text: String, to note: FloatingNote) async throws -> FloatingNote {
        let file = URL(fileURLWithPath: note.id)
        do {
            switch try NoteDesk.save(text, to: file, readAt: note.modified) {
            case let .written(modified):
                return FloatingNote(id: note.id, name: note.name, modified: modified)
            case let .keptBeside(copy):
                return FloatingNote(id: copy.path, name: copy.deletingPathExtension().lastPathComponent, modified: NoteDesk.modified(copy))
            }
        } catch {
            throw FloatingNoteError.failed(error.localizedDescription)
        }
    }

    func makeNote(named name: String) async throws -> FloatingNote {
        guard let folder else { throw FloatingNoteError.noFolder }
        do {
            let file = try NoteFiles.write(name, in: folder)
            record(.note(file))
            return FloatingNote(id: file.path, name: file.deletingPathExtension().lastPathComponent, modified: NoteDesk.modified(file))
        } catch {
            throw FloatingNoteError.failed(error.localizedDescription)
        }
    }

    /// A look at the file's date is all a check costs; the file is read only when the date moved.
    func changes(to note: FloatingNote) async -> (note: FloatingNote, text: String)? {
        let file = URL(fileURLWithPath: note.id)
        guard let onDisk = NoteDesk.modified(file), onDisk != note.modified, let read = NoteDesk.read(file) else { return nil }
        return (FloatingNote(id: note.id, name: note.name, modified: read.modified), read.text)
    }
}

/// One note kept in Floe's support folder, for a notes app Floe can hand text to but not read back.
/// The text waits here until it is sent.
final class ScratchNoteStore: FloatingNoteStore {
    static let note = FloatingNote(id: "scratch", name: String(localized: "Scratch Note", bundle: .floe, comment: "The name of the one note the floating note keeps when the notes app cannot be read back."))

    let app: NotesApp
    let appName: String
    private let file: URL

    init(app: NotesApp, appName: String, file: URL = Paths.scratchNote) {
        self.app = app
        self.appName = appName
        self.file = file
    }

    var place: String {
        String(localized: "Kept on this Mac until you send it to \(appName)", bundle: .floe, comment: "Where the scratch note is stored. The placeholder is the name of an app.")
    }

    var sendsTo: NoteRecipient? {
        NoteRecipient(app: app, name: appName)
    }

    func notes() async throws -> [FloatingNote] {
        [Self.note]
    }

    func read(_: FloatingNote) async throws -> (note: FloatingNote, text: String) {
        do {
            return (Self.note, try String(contentsOf: file, encoding: .utf8))
        } catch CocoaError.fileReadNoSuchFile {
            return (Self.note, "")
        } catch {
            throw FloatingNoteError.unreadable
        }
    }

    func save(_ text: String, to _: FloatingNote) async throws -> FloatingNote {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
            return Self.note
        } catch {
            throw FloatingNoteError.failed(error.localizedDescription)
        }
    }

    /// There is only the one: a new note would be the same file.
    func makeNote(named _: String) async throws -> FloatingNote {
        Self.note
    }

    func changes(to _: FloatingNote) async -> (note: FloatingNote, text: String)? {
        nil
    }
}
