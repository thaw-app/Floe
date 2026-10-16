//
//  NoteDeskTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Synchronization
import Testing

@MainActor final class NoteDeskTests {
    private let vault = FileManager.default.temporaryDirectory.appendingPathComponent("floe-notes-\(UUID().uuidString)", isDirectory: true)
    private var said: [String] = []
    private var receipts: [Receipt] = []
    private var opened: [URL] = []
    private var closed = 0

    init() throws {
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try write("# Plan\n\n- [ ] ship\n", to: "Plan.md", changed: 300)
        try write("ideas\n", to: "Projects/Ideas.md", changed: 200)
        try write("old\n", to: "Old.md", changed: 100)
        try write("not a note", to: "picture.png", changed: 400)
    }

    deinit {
        try? FileManager.default.removeItem(at: vault)
    }

    private func write(_ text: String, to name: String, changed seconds: TimeInterval) throws {
        let file = vault.appendingPathComponent(name)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: file.path)
    }

    private func text(of name: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(name), encoding: .utf8)
    }

    private func makeDesk(app: NotesApp = .folder, folder: String? = nil) async -> NoteDeskModel {
        let desk = NoteDeskModel(app: app, folder: folder ?? vault.path, record: { self.receipts.append($0) }, open: { self.opened.append($0) })
        desk.host = ModeHost(showHUD: { self.said.append($0) }, close: { self.closed += 1 })
        await desk.start().value
        return desk
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    // MARK: The folder

    @Test func theNotesAreTheMarkdownFilesNewestFirstFoldersIncluded() {
        #expect(NoteDesk.notes(in: vault).map(\.name) == ["Plan", "Ideas", "Old"])
        #expect(NoteDesk.matching(NoteDesk.notes(in: vault), query: "ide").map(\.name) == ["Ideas"])
        #expect(NoteDesk.notes(in: vault.appendingPathComponent("nowhere")).isEmpty)
    }

    @Test func theAppThatOwnsAFolderIsKnownByWhatItLeavesInIt() throws {
        #expect(NoteDesk.owner(of: vault) == nil)
        #expect(NoteDesk.placeLabel(folder: vault, owner: nil) == "Kept in the folder \(vault.lastPathComponent)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        #expect(NoteDesk.owner(of: vault) == "Obsidian")
        #expect(NoteDesk.owner(of: vault.appendingPathComponent("Projects")) == "Obsidian", "a folder inside a vault is the vault's")
        #expect(NoteDesk.placeLabel(folder: vault, owner: "Obsidian") == "Kept in Obsidian: \(vault.lastPathComponent)")
        let note = vault.appendingPathComponent("Plan.md")
        #expect(NoteDesk.link(to: note, owner: "Obsidian").scheme == "obsidian")
        #expect(NoteDesk.link(to: note, owner: "Obsidian").absoluteString.contains("path="))
        #expect(NoteDesk.link(to: note, owner: nil) == note)
    }

    // MARK: Reading

    @Test func theNewestNoteIsOnScreenAndTheArrowsMoveThroughTheList() async throws {
        let desk = await makeDesk()
        #expect(desk.place == .folder(vault, owner: nil))
        #expect(desk.text == "# Plan\n\n- [ ] ship\n")
        #expect(try desk.handleKey(key(125), []))
        #expect(desk.selection == 1)
        #expect(desk.text == "ideas\n")
        desk.select(9)
        #expect(desk.selected?.name == "Old")
        desk.query = "pla"
        #expect(desk.filtered.map(\.name) == ["Plan"])
        #expect(desk.text == "# Plan\n\n- [ ] ship\n")
    }

    @Test func aNotesAppThatIsNoFolderSaysSoAndReadsNothing() async {
        let desk = await makeDesk(app: .appleNotes)
        #expect(desk.place == .elsewhere("Apple Notes"))
        #expect(desk.notes.isEmpty)
        let unset = await makeDesk(folder: "")
        #expect(unset.place == .elsewhere(""))
    }

    @Test func whatAnotherAppWritesShowsUnlessTheEditorHoldsChanges() async throws {
        let desk = await makeDesk()
        try write("# Plan\n\nchanged in Obsidian\n", to: "Plan.md", changed: 500)
        desk.reloadIfChanged()
        #expect(desk.text == "# Plan\n\nchanged in Obsidian\n")
    }

    // MARK: Writing

    @Test func aPauseInTypingSavesWithoutBeingAsked() async throws {
        let desk = await makeDesk()
        desk.toggleEditing()
        desk.text = "# Plan\n\n- [x] ship\n"
        desk.text = "# Plan\n\n- [x] ship it\n"
        for _ in 0 ..< 300 where try text(of: "Plan.md") != desk.text {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try text(of: "Plan.md") == "# Plan\n\n- [x] ship it\n")
        desk.close()
    }

    @Test func whatIsTypedIsWrittenToTheFileAndNothingElseIs() async throws {
        let desk = await makeDesk()
        desk.flush()
        #expect(try text(of: "Plan.md") == "# Plan\n\n- [ ] ship\n", "a note that was only read is not written")
        desk.toggleEditing()
        desk.text = "# Plan\n\n- [x] ship\n"
        desk.select(1)
        #expect(try text(of: "Plan.md") == "# Plan\n\n- [x] ship\n", "leaving a note saves it")
        #expect(try text(of: "Projects/Ideas.md") == "ideas\n")
        #expect(said.isEmpty)
    }

    @Test func aNoteChangedElsewhereWhileItWasEditedIsNotOverwritten() async throws {
        let desk = await makeDesk()
        desk.toggleEditing()
        desk.text = "mine\n"
        try write("theirs\n", to: "Plan.md", changed: 900)
        desk.flush()
        #expect(try text(of: "Plan.md") == "theirs\n")
        let copies = try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { $0.hasPrefix("Plan (Floe ") }
        #expect(copies.count == 1)
        #expect(try text(of: #require(copies.first)) == "mine\n")
        #expect(said.count == 1)
        desk.text = "mine, and more\n"
        desk.flush()
        #expect(try text(of: #require(copies.first)) == "mine, and more\n", "the editor goes on in its own copy")
        #expect(try text(of: "Plan.md") == "theirs\n")
    }

    @Test func aNoteReadWithoutADateIsNotOverwrittenWhenItsTextChangedSince() throws {
        let note = vault.appendingPathComponent("Plan.md")
        try write("theirs\n", to: "Plan.md", changed: 900)
        guard case let .keptBeside(copy) = try NoteDesk.save("mine\n", to: note, readAt: nil) else {
            Issue.record("a note with no date of its own was written over")
            return
        }
        #expect(try text(of: "Plan.md") == "theirs\n")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "mine\n")
        #expect(try NoteDesk.save("theirs\n", to: note, readAt: nil) == .written(modified: NoteDesk.modified(note)), "the same text is no conflict")
    }

    @Test func aListingThatFinishesAfterANewerOneIsDropped() async {
        let isFirst = Mutex(true)
        let (entries, entered) = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        let desk = NoteDeskModel(app: .folder, folder: vault.path, list: { folder in
            // The first listing is held until the second one has finished.
            guard isFirst.withLock({ defer { $0 = false }; return $0 }) else { return NoteDesk.notes(in: folder) }
            entered.yield()
            release.wait()
            return []
        })
        let older = desk.start()
        var entry = entries.makeAsyncIterator()
        await entry.next()
        await desk.start().value
        release.signal()
        await older.value
        #expect(desk.notes.map(\.name) == ["Plan", "Ideas", "Old"], "the older, empty listing does not replace the newer one")
    }

    @Test func aNewNoteTakesItsNameFromTheSearchAndLeavesAReceipt() async throws {
        let desk = await makeDesk()
        desk.query = "Call Ana"
        await desk.makeNote().value
        #expect(try text(of: "Call Ana.md") == "Call Ana\n")
        #expect(receipts.map(\.subject) == ["Call Ana"])
        #expect(receipts.first?.kind == .note)
        #expect(desk.query.isEmpty)
        #expect(desk.isEditing)
        #expect(desk.selected?.name == "Call Ana")
        #expect(desk.text == "Call Ana\n")
    }

    // MARK: Keys

    @Test func whileANoteIsWrittenOnlyEscapeAndTheCommandsAreTaken() async throws {
        let desk = await makeDesk()
        #expect(try desk.handleKey(key(36), []), "Return starts writing")
        #expect(desk.isEditing)
        #expect(try !desk.handleKey(key(125), []), "an arrow is the text's")
        #expect(try !desk.handleKey(key(36), []), "and so is Return")
        #expect(try desk.handleKey(key(53), []))
        #expect(!desk.isEditing)
        #expect(try desk.handleKey(key(14), .command), "Command-E does the same")
        #expect(desk.isEditing)
        #expect(try desk.handleKey(key(31), .command))
        #expect(opened.map(\.lastPathComponent) == ["Plan.md"])
    }

    @Test func escapeClearsTheSearchThenLeavesTheView() async throws {
        let desk = await makeDesk()
        desk.query = "pla"
        #expect(try desk.handleKey(key(53), []))
        #expect(desk.query.isEmpty)
        #expect(closed == 0)
        #expect(try desk.handleKey(key(53), []))
        #expect(closed == 1)
    }

    // MARK: The launcher

    @Test func theCommandOpensTheViewAndLeavingItSavesWhatWasTyped() async throws {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.notesApp = .folder
        settings.notesFolder = vault.path
        let model = LauncherModel(settings: settings, usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        #expect(RootItem.noteDesk.title == "Browse Notes")
        #expect(LauncherModel.hotkeyViews.map(\.id).contains(RootItem.noteDeskKey))
        model.activate(.noteDesk)
        let desk = try #require(model.noteDesk)
        await desk.start().value
        #expect(!model.panelState.isRootSearch)
        desk.toggleEditing()
        desk.text = "typed and then the panel closed\n"
        model.reset()
        #expect(model.noteDesk == nil)
        #expect(try text(of: "Plan.md") == "typed and then the panel closed\n")
    }
}
