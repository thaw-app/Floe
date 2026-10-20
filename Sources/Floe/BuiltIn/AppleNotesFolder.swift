//
//  AppleNotesFolder.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The scripts that read and write the notes of one folder in Apple Notes, the one named Floe in the
/// default account. Every script finds a note through that folder, so a note anywhere else is never
/// read or written. Pure text in and out, so each is tested without Notes.
nonisolated enum AppleNotesFolder {
    static let name = "Floe"
    /// Between a note's id and its name, and after each note, in what a script returns. Neither is typed in a name.
    static let fieldSeparator = Character(Unicode.Scalar(fieldCode))
    static let noteSeparator = Character(Unicode.Scalar(noteCode))
    private static let fieldCode: UInt8 = 31
    private static let noteCode: UInt8 = 30

    /// Wraps a script's lines in the folder, which is made when it is missing.
    static func inFolder(_ lines: String) -> String {
        let folder = AppleScript.literal(name)
        return """
        tell application "Notes"
            set theAccount to default account
            if not (exists folder \(folder) of theAccount) then make new folder at theAccount with properties {name:\(folder)}
            set theFolder to folder \(folder) of theAccount
        \(lines.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n"))
        end tell
        """
    }

    /// Each note of the folder as its id and its name.
    static func listScript() -> String {
        inFolder("""
        set output to ""
        repeat with theNote in notes of theFolder
            set output to output & (id of theNote) & (character id \(fieldCode)) & (name of theNote) & (character id \(noteCode))
        end repeat
        return output
        """)
    }

    /// The note's text without its formatting. Its first line is its name.
    static func readScript(id: String) -> String {
        inFolder("return plaintext of note id \(AppleScript.literal(id)) of theFolder")
    }

    /// Replaces the note's body with the text, and answers with the name Notes takes from its first line.
    static func writeScript(_ text: String, id: String) -> String {
        inFolder("""
        set theNote to note id \(AppleScript.literal(id)) of theFolder
        set body of theNote to \(AppleScript.literal(Notes.appleNotesHTML(text)))
        return name of theNote
        """)
    }

    /// A new note in the folder, with the text as its first line, answered as its id and its name.
    static func createScript(_ text: String) -> String {
        inFolder("""
        set theNote to make new note at theFolder with properties {body:\(AppleScript.literal(Notes.appleNotesHTML(text)))}
        return (id of theNote) & (character id \(fieldCode)) & (name of theNote)
        """)
    }

    /// Brings Notes forward with the note on screen.
    static func showScript(id: String) -> String {
        inFolder("""
        show note id \(AppleScript.literal(id)) of theFolder
        activate
        """)
    }

    /// What the list script returned, as notes. A piece without an id is left out.
    static func notes(from output: String) -> [FloatingNote] {
        output.split(separator: noteSeparator).compactMap { note(from: String($0)) }
    }

    static func note(from output: String) -> FloatingNote? {
        let fields = output.split(separator: fieldSeparator, maxSplits: 1, omittingEmptySubsequences: false)
        let id = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return FloatingNote(id: id, name: fields.count > 1 ? String(fields[1]) : "")
    }
}

/// The notes of Floe's folder in Apple Notes, through scripts that run off the main thread.
final class AppleNotesStore: FloatingNoteStore {
    private let run: AppleScriptRunner

    init(run: @escaping AppleScriptRunner = AppleScript.run) {
        self.run = run
    }

    var place: String {
        String(localized: "Kept in Notes, in the folder \(AppleNotesFolder.name)", bundle: .floe, comment: "Where the notes on screen are stored. Notes is Apple's notes app; the placeholder is a folder's name.")
    }

    var sendsTo: NoteRecipient? {
        nil
    }

    func notes() async throws -> [FloatingNote] {
        try await AppleNotesFolder.notes(from: perform(AppleNotesFolder.listScript()))
    }

    func read(_ note: FloatingNote) async throws -> (note: FloatingNote, text: String) {
        try await (note, perform(AppleNotesFolder.readScript(id: note.id)))
    }

    func save(_ text: String, to note: FloatingNote) async throws -> FloatingNote {
        let name = try await perform(AppleNotesFolder.writeScript(text, id: note.id))
        return FloatingNote(id: note.id, name: name.isEmpty ? note.name : name)
    }

    func makeNote(named name: String) async throws -> FloatingNote {
        guard let note = try await AppleNotesFolder.note(from: perform(AppleNotesFolder.createScript(name))) else {
            throw FloatingNoteError.failed(String(localized: "Notes made no note", bundle: .floe, comment: "Notes is Apple's notes app."))
        }
        return note
    }

    var opener: String? {
        String(localized: "Notes", bundle: .floe, comment: "The name of Apple's notes app, on a button that opens a note in it.")
    }

    var placeIcon: String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: NotesApp.appleNotes.bundleID ?? "")?.path
    }

    func open(_ note: FloatingNote) async throws {
        _ = try await perform(AppleNotesFolder.showScript(id: note.id))
    }

    /// Asking Notes every few seconds would cost a script each time: what Notes changes shows when the note is opened again.
    func changes(to _: FloatingNote) async -> (note: FloatingNote, text: String)? {
        nil
    }

    /// Hands the script to the runner off the main thread, and turns a refusal into the error the window explains.
    private func perform(_ source: String) async throws -> String {
        let run = run
        switch await Task.detached(priority: .userInitiated, operation: { await run(source) }).value {
        case let .text(text): return text
        case .refused: throw FloatingNoteError.refused
        case .failed: throw FloatingNoteError.failed(String(localized: "Notes didn’t answer", bundle: .floe, comment: "Notes is Apple's notes app."))
        }
    }
}
