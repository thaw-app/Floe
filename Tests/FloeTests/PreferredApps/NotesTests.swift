//
//  NotesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing

@MainActor
struct NotesTests {
    private func makeModel(app: NotesApp) -> LauncherModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "floe-notes-tests-\(UUID().uuidString)")!)
        settings.notesApp = app
        return LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []))
    }

    @Test func aQueryThatStartsWithNoteIsANewNoteWithTheRestAsItsText() throws {
        let request = try #require(Notes.request(in: "Note buy milk & eggs ", app: .appleNotes))
        #expect(request.action == .new)
        #expect(request.text == "buy milk & eggs")
        #expect(Notes.request(in: "note", app: .appleNotes) == nil, "the keyword alone is a search for it")
        #expect(Notes.request(in: "note   ", app: .appleNotes) == nil)
        #expect(Notes.request(in: "notes app", app: .appleNotes) == nil, "a longer word is not the keyword")
    }

    @Test func onlyAntinoteCanAppend() throws {
        #expect(Notes.request(in: "append call back", app: .appleNotes) == nil)
        #expect(Notes.request(in: "append call back", app: .custom) == nil)
        let request = try #require(Notes.request(in: "append call back", app: .antinote))
        #expect(request.action == .append)
        #expect(NotesApp.allCases.filter { $0.actions.contains(.append) } == [.antinote])
    }

    @Test func antinoteGetsItsDocumentedLinksWithTheTextEscaped() {
        let new = Notes.url(.new, text: "a&b=c d?", app: .antinote, template: "")
        #expect(new?.absoluteString == "antinote://x-callback-url/createNote?content=a%26b%3Dc%20d%3F")
        let append = Notes.url(.append, text: "línea\n2", app: .antinote, template: "")
        #expect(append?.absoluteString == "antinote://x-callback-url/appendToCurrent?content=l%C3%ADnea%0A2")
        #expect(Notes.url(.new, text: "", app: .antinote, template: "")?.absoluteString == "antinote://", "no text opens the app")
    }

    @Test func aTemplatePutsTheEscapedTextWhereThePlaceholderIs() {
        let url = Notes.url(.new, text: "buy milk", app: .custom, template: "bear://x-callback-url/create?text={text}")
        #expect(url?.absoluteString == "bear://x-callback-url/create?text=buy%20milk")
        #expect(Notes.url(.new, text: "x", app: .appleNotes, template: "ignored://{text}") == nil, "Apple Notes is scripted, not linked")
    }

    @Test func theAppleNotesScriptEscapesHTMLAndQuotesAndKeepsLines() {
        let script = Notes.appleNotesScript(text: "Say \"hi\" <now>\n\nA & B \\ C")
        #expect(script == #"tell application "Notes" to make new note with properties {body:"<div>Say \"hi\" &lt;now&gt;</div><div><br></div><div>A &amp; B \\ C</div>"}"#)
        #expect(NSAppleScript(source: script) != nil)
        #expect(Notes.appleNotesScript(text: "").contains("show (make new note)"), "without text Notes opens on a new note")
    }

    @Test(arguments: NoteAction.allCases)
    func everyActionHasASymbolThatExistsAndATitleForBothStates(action: NoteAction) {
        #expect(NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) != nil)
        #expect(action.title(text: "") != action.title(text: "x"))
        #expect(action.title(text: "buy milk").contains("“buy milk”"))
    }

    @Test func theSearchLeadsWithTheNoteItWouldMakeAndListsItOnce() throws {
        let model = makeModel(app: .antinote)
        model.query = "note buy milk"
        let first = try #require(model.results.first?.item)
        #expect(first.title == "New Note “buy milk”")
        #expect(first.kind == "Notes")
        #expect(model.results.filter { $0.id == "note:new" }.count == 1)

        model.query = "append call back"
        #expect(model.results.first?.item.title == "Append “call back” to Current Note")
    }

    @Test func theBareActionsAreFoundByNameAndFollowTheChosenApp() {
        let antinote = makeModel(app: .antinote)
        antinote.query = "new note"
        #expect(antinote.results.first?.item.id == "note:new")
        antinote.query = "append to"
        #expect(antinote.results.contains { $0.id == "note:append" })

        let apple = makeModel(app: .appleNotes)
        apple.query = "append to"
        #expect(!apple.results.contains { $0.id == "note:append" }, "Apple Notes has no current note to add to")
    }

    @Test func theNotesAppAndItsLinkComeBackAfterASave() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-notes-tests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.notesApp == .appleNotes, "the app every Mac has is the default")
        settings.notesApp = .custom
        settings.notesURLTemplate = "bear://x-callback-url/create?text={text}"
        settings.save()
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.notesApp == .custom)
        #expect(reloaded.notesURLTemplate == "bear://x-callback-url/create?text={text}")
    }

    private func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Noon on 8 October 2026, in this Mac's time zone.
    private var noon: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12, minute: 5)) ?? Date()
    }

    @Test func aFolderOfNotesTakesNewNotesAndAppendsToTheDaysNote() {
        #expect(NotesApp.folder.actions == [.new, .today])
        #expect(NotesApp.folder.title == "A Folder of Notes")
        #expect(Notes.request(in: "note buy milk", app: .folder)?.action == .new)
        #expect(Notes.request(in: "append call the bank", app: .folder)?.action == .today)
        #expect(Notes.request(in: "append call the bank", app: .appleNotes) == nil, "an app with no day's note has nothing to append to")
        #expect(NoteAction.today.title(text: "call the bank") == "Append “call the bank” to Today’s Note")
        #expect(NoteAction.today.title(text: "") == "Open Today’s Note")
        #expect(Notes.url(.new, text: "x", app: .folder, template: "") == nil, "a file is written, no link is opened")
    }

    @Test func aNotesFileIsNamedByItsFirstLine() {
        let taken: Set = ["Buy milk.md", "Buy milk 2.md"]
        #expect(NoteFiles.fileName(for: "Call the bank\nabout the card", now: noon) { _ in false } == "Call the bank.md")
        #expect(NoteFiles.fileName(for: "# Ideas: launch/pricing", now: noon) { _ in false } == "Ideas  launch pricing.md", "what a file name cannot hold is taken out")
        #expect(NoteFiles.fileName(for: "Buy milk", now: noon) { taken.contains($0) } == "Buy milk 3.md", "a name that is taken is numbered")
        #expect(NoteFiles.fileName(for: "...", now: noon) { _ in false } == "2026-10-08 12.05.md", "nothing left of the first line: the date and time")
        #expect(NoteFiles.fileName(for: String(repeating: "a", count: 200), now: noon) { _ in false }.count == 63)
        #expect(NoteFiles.todayName(now: noon) == "2026-10-08.md")
    }

    @Test func aLineGoesOnALineOfItsOwn() {
        #expect(NoteFiles.appended("first", to: "") == "first\n")
        #expect(NoteFiles.appended("second", to: "first\n") == "first\nsecond\n")
        #expect(NoteFiles.appended("second", to: "first") == "first\nsecond\n", "a file that did not end its last line")
    }

    @Test func appendingNeverReplacesANoteThatCannotBeReadAsUTF8() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = NoteFiles.dayFile(in: folder, now: noon)
        let original = try #require("An important existing note".data(using: .utf16))
        try original.write(to: file)

        #expect(throws: CocoaError.self) {
            try NoteFiles.append("new line", in: folder, now: noon)
        }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func notesAreWrittenAsFilesAndNeverOverOneThatIsThere() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var opened: [String] = []
        let open: (URL) -> Void = { opened.append($0.lastPathComponent) }

        #expect(NoteFiles.perform(.new, text: "Buy milk", folder: folder.path, now: noon, open: open) == "Saved Buy milk")
        #expect(NoteFiles.perform(.new, text: "Buy milk", folder: folder.path, now: noon, open: open) == "Saved Buy milk 2")
        #expect(try String(contentsOf: folder.appendingPathComponent("Buy milk.md"), encoding: .utf8) == "Buy milk\n")

        #expect(NoteFiles.perform(.today, text: "call the bank", folder: folder.path, now: noon, open: open) == "Added to today’s note")
        #expect(NoteFiles.perform(.today, text: "renew passport", folder: folder.path, now: noon, open: open) == "Added to today’s note")
        #expect(try String(contentsOf: folder.appendingPathComponent("2026-10-08.md"), encoding: .utf8) == "call the bank\nrenew passport\n")
        #expect(opened.isEmpty)

        #expect(NoteFiles.perform(.today, text: "", folder: folder.path, now: noon, open: open) == nil)
        #expect(NoteFiles.perform(.new, text: "", folder: folder.path, now: noon, open: open) == nil)
        #expect(opened == ["2026-10-08.md", folder.lastPathComponent], "without text the day's note, or the folder, is opened to write in")
    }

    @Test func withNoFolderChosenTheNoteIsNotWrittenAnywhere() throws {
        #expect(NoteFiles.perform(.new, text: "x", folder: "") == "Choose a folder for your notes in Settings")
        #expect(NoteFiles.perform(.new, text: "x", folder: "/floe-no-such-folder-\(UUID().uuidString)") == "Choose a folder for your notes in Settings")
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a-file")
        try Data().write(to: file)
        #expect(NoteFiles.perform(.new, text: "x", folder: file.path) == "Choose a folder for your notes in Settings", "a file is not a folder")
    }

    @MainActor @Test func theFolderIsKeptInSettings() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-notes-tests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        settings.notesApp = .folder
        settings.notesFolder = "/Users/me/Notes"
        settings.save()
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.notesApp == .folder)
        #expect(reloaded.notesFolder == "/Users/me/Notes")
    }

    @Test func theDaysNoteGoesWhereTheAppThatOwnsTheFolderKeepsIt() throws {
        let plain = try scratchFolder()
        let octarine = try scratchFolder()
        let obsidian = try scratchFolder()
        let obsidianSet = try scratchFolder()
        defer { [plain, octarine, obsidian, obsidianSet].forEach { try? FileManager.default.removeItem(at: $0) } }
        try FileManager.default.createDirectory(at: octarine.appendingPathComponent(".octarine"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: obsidian.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: obsidianSet.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try Data(#"{"folder":"Journal/Daily","format":"YYYY-MM-DD"}"#.utf8).write(to: obsidianSet.appendingPathComponent(".obsidian/daily-notes.json"))

        #expect(NoteFiles.dayFile(in: plain, now: noon).path == plain.appendingPathComponent("2026-10-08.md").path)
        #expect(NoteFiles.dayFile(in: octarine, now: noon).path == octarine.appendingPathComponent("Daily/2026-10-08.md").path)
        #expect(NoteFiles.dayFile(in: obsidian, now: noon).path == obsidian.appendingPathComponent("2026-10-08.md").path, "a vault with no setting keeps it at the top")
        #expect(NoteFiles.dayFile(in: obsidianSet, now: noon).path == obsidianSet.appendingPathComponent("Journal/Daily/2026-10-08.md").path)

        #expect(NoteFiles.perform(.today, text: "renew passport", folder: octarine.path, now: noon) == "Added to today’s note")
        #expect(try String(contentsOf: octarine.appendingPathComponent("Daily/2026-10-08.md"), encoding: .utf8) == "renew passport\n", "the folder is made when the day's note is its first")
        try Data("existing".utf8).write(to: obsidian.appendingPathComponent("2026-10-08.md"))
        _ = NoteFiles.perform(.today, text: "added", folder: obsidian.path, now: noon)
        #expect(try String(contentsOf: obsidian.appendingPathComponent("2026-10-08.md"), encoding: .utf8) == "existing\nadded\n", "what the app wrote is kept")
    }

    @Test func theDayIsTheUsersOwnAndAnAppsNoteDatedInUTCIsStillFound() throws {
        let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 17, minute: 24)))
        #expect(NoteFiles.todayName(now: evening, in: pacific) == "2026-10-08.md", "the evening of the 8th where the user is")
        #expect(NoteFiles.todayName(now: evening, in: utc) == "2026-10-09.md", "is already the 9th in UTC")
        #expect(NoteFiles.stamp("yyyy-MM-dd HH.mm", evening, in: pacific) == "2026-10-08 17.24")

        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        let local = folder.appendingPathComponent(NoteFiles.todayName(now: now))
        let inUTC = folder.appendingPathComponent(NoteFiles.todayName(now: now, in: utc))
        #expect(NoteFiles.dayFile(in: folder, now: now).path == local.path, "with no note yet, the user's own day")
        if local.path != inUTC.path {
            try Data("the app's".utf8).write(to: inUTC)
            #expect(NoteFiles.dayFile(in: folder, now: now).path == inUTC.path, "the app's note for its today is the one to add to")
            try Data("mine".utf8).write(to: local)
            #expect(NoteFiles.dayFile(in: folder, now: now).path == local.path, "once the user's day has a note, that one")
        }
    }

    @Test func theFoldersAppsAlreadyKeepAreFoundFromTheirOwnLists() throws {
        let list = Data(#"{"vaults":{"b":{"path":"/Users/me/Vault","ts":1,"open":true},"a":{"path":"/Users/me/Archive"}}}"#.utf8)
        #expect(KnownNoteFolders.obsidianVaults(in: list) == ["/Users/me/Archive", "/Users/me/Vault"])
        #expect(KnownNoteFolders.obsidianVaults(in: nil).isEmpty)
        #expect(KnownNoteFolders.obsidianVaults(in: Data("not json".utf8)).isEmpty)
        #expect(KnownNoteFolders.octarineWorkspaces(database: URL(fileURLWithPath: "/floe-no-such-\(UUID().uuidString).sqlite")).isEmpty)
        #expect(KnownNoteFolders.Folder(app: "Obsidian", path: "/Users/me/Vault").title == "Obsidian: Vault")

        let home = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let vault = home.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let support = home.appendingPathComponent("Library/Application Support/obsidian")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["vaults": ["a": ["path": vault.path], "b": ["path": home.appendingPathComponent("Gone").path]]]).write(to: support.appendingPathComponent("obsidian.json"))
        #expect(KnownNoteFolders.all(home: home).map(\.title) == ["Obsidian: Vault"], "a vault that is no longer there is not offered")
    }

    @MainActor @Test func everyNotesChoiceHasAnIconInThePicker() {
        #expect(NotesApp.allCases.map(\.bundleID) == ["com.apple.Notes", "com.chabomakers.Antinote", nil, nil])
        #expect(NotesApp.allCases.map(\.symbol) == ["note.text", "note.text", "link", "folder"])
        for app in NotesApp.allCases {
            let icon = NotesAppPicker.icon(for: app)
            #expect(icon.size == NSSize(width: 16, height: 16), "\(app.rawValue) has a picture the size of the others")
            #expect(icon.isValid)
        }
    }
}
