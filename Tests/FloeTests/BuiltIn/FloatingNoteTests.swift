//
//  FloatingNoteTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// A store held in memory, which can be told to fail. What it was asked is kept for the tests to read.
private final class FakeNoteStore: FloatingNoteStore {
    var texts: [String: String]
    var order: [String]
    var saves: [(id: String, text: String)] = []
    var failsSaving = false
    var refuses = false
    var changedElsewhere: (note: FloatingNote, text: String)?
    let sendsTo: NoteRecipient?

    init(_ notes: [(String, String)] = [("Plan", "# Plan\n"), ("Ideas", "ideas\n")], sendsTo: NoteRecipient? = nil) {
        texts = Dictionary(uniqueKeysWithValues: notes)
        order = notes.map(\.0)
        self.sendsTo = sendsTo
    }

    var place: String {
        "memory"
    }

    func notes() async throws -> [FloatingNote] {
        if refuses {
            throw FloatingNoteError.refused
        }
        return order.map { FloatingNote(id: $0, name: $0) }
    }

    func read(_ note: FloatingNote) async throws -> (note: FloatingNote, text: String) {
        guard let text = texts[note.id] else { throw FloatingNoteError.unreadable }
        return (note, text)
    }

    func save(_ text: String, to note: FloatingNote) async throws -> FloatingNote {
        if failsSaving {
            throw FloatingNoteError.failed("disk full")
        }
        saves.append((note.id, text))
        texts[note.id] = text
        return note
    }

    func makeNote(named name: String) async throws -> FloatingNote {
        let id = name.isEmpty ? "Untitled" : name
        texts[id] = name
        order.insert(id, at: 0)
        return FloatingNote(id: id, name: id)
    }

    func changes(to _: FloatingNote) async -> (note: FloatingNote, text: String)? {
        defer { changedElsewhere = nil }
        return changedElsewhere
    }
}

@MainActor struct FloatingNoteModelTests {
    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    private func started(_ store: FakeNoteStore, pause: Duration = .seconds(60), send: @escaping (NoteAction, String, @escaping (String?) -> Void) -> Void = { _, _, done in done(nil) }) async -> FloatingNoteModel {
        var environment = FloatingNoteModel.Environment()
        environment.pause = pause
        environment.send = send
        environment.askForAutomation = {
            // No alert in a test.
        }
        let model = FloatingNoteModel(store: store, environment: environment)
        await model.start().value
        return model
    }

    @Test func theNewestNoteOpensAndSwitchingSavesTheOneOnScreenFirst() async {
        let store = FakeNoteStore()
        let model = await started(store)
        #expect(model.note?.name == "Plan")
        #expect(model.text == "# Plan\n")
        model.text = "# Plan\n\nship\n"
        await model.open(FloatingNote(id: "Ideas", name: "Ideas")).value
        #expect(store.saves.map(\.text) == ["# Plan\n\nship\n"])
        #expect(model.note?.name == "Ideas")
        #expect(model.text == "ideas\n")
        #expect(!model.hasUnsavedText)
    }

    @Test func aPauseInTypingSavesOnceWithTheLastText() async throws {
        let store = FakeNoteStore()
        let model = await started(store, pause: .milliseconds(30))
        model.text = "# Plan\n\na"
        model.text = "# Plan\n\nab"
        for _ in 0 ..< 300 where store.saves.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.saves.map(\.text) == ["# Plan\n\nab"])
        #expect(await model.commit(), "nothing is left to save")
        #expect(store.saves.count == 1, "a save that finds nothing new writes nothing")
        model.stop()
    }

    @Test func aFailedSaveKeepsTheTextAndTheWindowAndSaysWhy() async {
        let store = FakeNoteStore()
        let model = await started(store)
        var closed = 0
        model.close = { closed += 1 }
        store.failsSaving = true
        model.text = "typed before the disk filled"
        await model.requestClose().value
        #expect(closed == 0, "the window stays while the text is unsaved")
        #expect(model.text == "typed before the disk filled")
        #expect(model.status == "Couldn’t save the note: disk full")
        await model.open(FloatingNote(id: "Ideas", name: "Ideas")).value
        #expect(model.note?.name == "Plan", "a switch waits for the save")
        #expect(model.text == "typed before the disk filled")

        store.failsSaving = false
        await model.requestClose().value
        #expect(closed == 1)
        #expect(model.status == nil, "a save that works clears the reason")
        #expect(store.texts["Plan"] == "typed before the disk filled")
    }

    @Test func aRefusalAsksForAutomationAndListsNothing() async {
        let store = FakeNoteStore()
        store.refuses = true
        let model = await started(store)
        #expect(model.notes.isEmpty)
        #expect(model.note == nil)
        #expect(model.needsAutomation)
        #expect(model.status == "Floe needs permission to control Notes. Your text stays here until it can save.")
    }

    @Test func aNewNoteIsNamedByTheListSearchAndOpens() async {
        let store = FakeNoteStore()
        let model = await started(store)
        model.isSwitching = true
        model.query = "Groceries"
        await model.makeNote().value
        #expect(!model.isSwitching)
        #expect(model.note?.name == "Groceries")
        #expect(model.notes.first?.name == "Groceries")
    }

    @Test func whatChangedElsewhereShowsUnlessTheEditorHoldsChanges() async {
        let store = FakeNoteStore()
        let model = await started(store)
        store.changedElsewhere = (FloatingNote(id: "Plan", name: "Plan"), "# Plan\n\nfrom Obsidian\n")
        await model.reloadIfChanged().value
        #expect(model.text == "# Plan\n\nfrom Obsidian\n")

        model.text = "mine"
        store.changedElsewhere = (FloatingNote(id: "Plan", name: "Plan"), "theirs")
        await model.reloadIfChanged().value
        #expect(model.text == "mine")
    }

    @Test func theKeysCloseSwitchAndPickFromTheList() async throws {
        let store = FakeNoteStore()
        let model = await started(store)
        var closed = 0
        model.close = { closed += 1 }
        #expect(try model.handleKey(key(35), .command))
        #expect(model.isSwitching)
        #expect(try model.handleKey(key(125), []))
        #expect(model.selection == 1)
        #expect(try model.handleKey(key(53), []), "Escape puts the list away first")
        #expect(!model.isSwitching)
        #expect(closed == 0)
        #expect(try !model.handleKey(key(0), []), "a letter is the text's")
        #expect(try model.handleKey(key(13), .command))
        for _ in 0 ..< 100 where closed == 0 {
            await Task.yield()
        }
        #expect(closed == 1)
    }

    // MARK: The scratch note

    @Test func theScratchNoteIsSentAndThenCleared() async throws {
        let store = FakeNoteStore([("scratch", "")], sendsTo: NoteRecipient(app: .antinote, name: "Antinote"))
        var sent: [(NoteAction, String)] = []
        let model = await started(store) { action, text, done in
            sent.append((action, text))
            done(nil)
        }
        #expect(!model.listsNotes)
        #expect(try !model.handleKey(key(45), .command), "there is no new note to make")
        model.text = "call the bank"
        model.send(.append)
        #expect(sent.map(\.0) == [.append])
        #expect(sent.map(\.1) == ["call the bank"])
        #expect(model.text.isEmpty)
        #expect(await model.commit())
        #expect(store.texts["scratch"]?.isEmpty == true)
    }

    @Test func aScratchNoteThatCouldNotBeSentStays() async {
        let store = FakeNoteStore([("scratch", "")], sendsTo: NoteRecipient(app: .custom, name: "Bear"))
        let model = await started(store) { _, _, done in done("No app opens that URL") }
        model.text = "keep me"
        model.send()
        #expect(model.text == "keep me")
        #expect(model.status == "No app opens that URL")
    }
}

@MainActor final class FloatingNoteStoreTests {
    private let vault = FileManager.default.temporaryDirectory.appendingPathComponent("floe-floating-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try write("# Plan\n", to: "Plan.md", changed: 300)
        try write("old\n", to: "Old.md", changed: 100)
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

    @Test func theFolderSettingNamesAFolderOrNothing() {
        #expect(NoteDesk.folder(at: vault.path) == vault)
        #expect(NoteDesk.folder(at: "") == nil)
        #expect(NoteDesk.folder(at: vault.appendingPathComponent("Plan.md").path) == nil, "a file is no folder")
    }

    @Test func aFolderListsReadsAndWritesItsFiles() async throws {
        let store = FolderNoteStore(folder: vault)
        let notes = try await store.notes()
        #expect(notes.map(\.name) == ["Plan", "Old"])
        let read = try await store.read(notes[0])
        #expect(read.text == "# Plan\n")
        let saved = try await store.save("# Plan\n\nship\n", to: read.note)
        #expect(saved.id == read.note.id)
        #expect(try text(of: "Plan.md") == "# Plan\n\nship\n")
        #expect(await store.changes(to: saved) == nil, "its own write is no change")
    }

    @Test func aFileChangedOnDiskIsReadAgain() async throws {
        let store = FolderNoteStore(folder: vault)
        let read = try await store.read(try #require(store.notes().first))
        try write("# Plan\n\nfrom Obsidian\n", to: "Plan.md", changed: 500)
        let changed = try #require(await store.changes(to: read.note))
        #expect(changed.text == "# Plan\n\nfrom Obsidian\n")
        #expect(await store.changes(to: changed.note) == nil)
    }

    @Test func aFileChangedUnderTheEditorIsKeptAndTheTextGoesBesideIt() async throws {
        let store = FolderNoteStore(folder: vault)
        let read = try await store.read(try #require(store.notes().first))
        try write("theirs\n", to: "Plan.md", changed: 500)
        let saved = try await store.save("mine\n", to: read.note)
        #expect(saved.id != read.note.id)
        #expect(saved.name.hasPrefix("Plan (Floe "))
        #expect(try text(of: "Plan.md") == "theirs\n")
        #expect(try String(contentsOfFile: saved.id, encoding: .utf8) == "mine\n")
    }

    @Test func aNewNoteIsAFileWithAReceipt() async throws {
        var receipts: [Receipt] = []
        let store = FolderNoteStore(folder: vault) { receipts.append($0) }
        let made = try await store.makeNote(named: "Groceries")
        #expect(made.name == "Groceries")
        #expect(try text(of: "Groceries.md") == "Groceries\n")
        #expect(receipts.count == 1)
    }

    @Test func noFolderIsAnErrorThatSaysWhereToChooseOne() async {
        let store = FolderNoteStore(folder: nil)
        await #expect(throws: FloatingNoteError.noFolder) { try await store.notes() }
        #expect(FloatingNoteError.noFolder.message(saving: false) == "Choose a folder for your notes in Settings")
    }

    @Test func theFolderModelTakesWhatAnotherAppWrote() async throws {
        let model = FloatingNoteModel(store: FolderNoteStore(folder: vault))
        await model.start().value
        #expect(model.text == "# Plan\n")
        try write("# Plan\n\nfrom Obsidian\n", to: "Plan.md", changed: 500)
        await model.reloadIfChanged().value
        #expect(model.text == "# Plan\n\nfrom Obsidian\n")
        model.stop()
    }

    @Test func theScratchNoteIsAFileThatStartsEmpty() async throws {
        let file = vault.appendingPathComponent("Support/Scratch Note.md")
        let store = ScratchNoteStore(app: .antinote, appName: "Antinote", file: file)
        #expect(store.sendsTo == NoteRecipient(app: .antinote, name: "Antinote"))
        let read = try await store.read(ScratchNoteStore.note)
        #expect(read.text.isEmpty)
        _ = try await store.save("waiting", to: read.note)
        #expect(try await store.read(read.note).text == "waiting")
        #expect(try await store.notes().count == 1)
    }

    @Test func eachNotesAppGetsItsStore() {
        #expect(FloatingNoteStores.store(for: .folder, folder: vault.path, template: "", record: { _ in }) is FolderNoteStore)
        #expect(FloatingNoteStores.store(for: .appleNotes, folder: "", template: "", record: { _ in }) is AppleNotesStore)
        let antinote = FloatingNoteStores.store(for: .antinote, folder: "", template: "", record: { _ in })
        #expect(antinote.sendsTo == NoteRecipient(app: .antinote, name: "Antinote"))
        #expect(FloatingNoteStores.appName(for: .custom, template: "not a link") == "Another App")
    }
}

@MainActor struct AppleNotesFolderTests {
    @Test func theBodyIsEscapedHTMLALineADiv() {
        #expect(Notes.appleNotesHTML("Say \"hi\" <now>\n\nA & B \\ C") == #"<div>Say "hi" &lt;now&gt;</div><div><br></div><div>A &amp; B \ C</div>"#)
        #expect(Notes.appleNotesHTML("one\r\ntwo") == "<div>one</div><div>two</div>", "a Windows line break is one line break")
    }

    @Test func aWriteEscapesQuotesAndBackslashesForAppleScript() {
        let script = AppleNotesFolder.writeScript("Say \"hi\" <b> & \\n\nnext", id: "x-coredata://A/ICNote/p1")
        #expect(script.contains(#"set theNote to note id "x-coredata://A/ICNote/p1" of theFolder"#))
        #expect(script.contains(#"set body of theNote to "<div>Say \"hi\" &lt;b&gt; &amp; \\n</div><div>next</div>""#))
        #expect(NSAppleScript(source: script) != nil)
    }

    @Test func everyScriptReachesNotesOnlyThroughFloesFolder() {
        let scripts = [
            AppleNotesFolder.listScript(),
            AppleNotesFolder.readScript(id: "p1"),
            AppleNotesFolder.writeScript("text", id: "p1"),
            AppleNotesFolder.createScript("Groceries"),
        ]
        for script in scripts {
            #expect(script.hasPrefix("tell application \"Notes\"\n    set theAccount to default account\n"))
            #expect(script.contains(#"if not (exists folder "Floe" of theAccount) then make new folder at theAccount with properties {name:"Floe"}"#))
            #expect(script.contains(#"set theFolder to folder "Floe" of theAccount"#))
        }
        #expect(AppleNotesFolder.readScript(id: #"p1" of every note"#).contains(#"note id "p1\" of every note" of theFolder"#), "an id stays one literal")
        #expect(AppleNotesFolder.readScript(id: "p1").contains("return plaintext of note id \"p1\" of theFolder"))
        #expect(AppleNotesFolder.listScript().contains("repeat with theNote in notes of theFolder"))
        #expect(AppleNotesFolder.createScript("Groceries").contains(#"make new note at theFolder with properties {body:"<div>Groceries</div>"}"#))
    }

    @Test func theListIsReadFromTheSeparatorsTheScriptPutsIn() {
        let output = "p1\u{1F}Plan\u{1E}p2\u{1F}Tabs\tand more\u{1E}\u{1F}no id\u{1E}"
        #expect(AppleNotesFolder.notes(from: output) == [FloatingNote(id: "p1", name: "Plan"), FloatingNote(id: "p2", name: "Tabs\tand more")])
        #expect(AppleNotesFolder.note(from: "p3\u{1F}New Note") == FloatingNote(id: "p3", name: "New Note"))
        #expect(AppleNotesFolder.notes(from: "").isEmpty)
    }

    @Test func theStoreRunsItsScriptsOffTheMainThreadAndExplainsARefusal() async throws {
        let threads = ThreadLog()
        let store = AppleNotesStore { source in
            let reads = source.contains("plaintext")
            threads.note(reads ? "read" : "list")
            return reads ? .refused : .text("p1\u{1F}Plan\u{1E}")
        }
        #expect(try await store.notes() == [FloatingNote(id: "p1", name: "Plan")])
        await #expect(throws: FloatingNoteError.refused) { try await store.read(FloatingNote(id: "p1", name: "Plan")) }
        #expect(threads.onMain == ["list": false, "read": false])
    }

    @Test func aSaveTakesTheNameNotesGaveTheNote() async throws {
        let store = AppleNotesStore { _ in .text("Shopping") }
        let saved = try await store.save("Shopping\nmilk", to: FloatingNote(id: "p1", name: "Plan"))
        #expect(saved == FloatingNote(id: "p1", name: "Shopping"))
        let failing = AppleNotesStore { _ in .failed }
        await #expect(throws: FloatingNoteError.self) { try await failing.save("x", to: saved) }
    }
}

@MainActor struct FloatingNoteCommandTests {
    @Test func theCommandHasARootRowAKeyForAnAliasAndAHotkey() {
        #expect(RootItem.floatingNote.id == "builtin:floating-note")
        #expect(RootItem.floatingNote.settingsKey == RootItem.floatingNoteKey)
        #expect(RootItem.floatingNote.title == "Floating Note")
        #expect(RootItem.floatingNote.kind == "Floe")
        #expect(LauncherModel.hotkeyViews.map(\.id).contains(RootItem.floatingNoteKey))
        #expect(SearchIndex.commandsEntries.contains { $0.id == "commands.floatingNoteHotkey" })
    }

    @Test func runningItHidesTheLauncherAndOpensTheWindow() {
        let defaults = MemoryDefaults()
        let launcher = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        var asked: [String] = []
        launcher.panelHost.hidePanel = { asked.append("hide") }
        launcher.panelHost.showFloatingNote = { asked.append("note") }
        launcher.activate(.floatingNote)
        #expect(asked == ["hide", "note"])
        launcher.runFromHotkey(.floatingNote)
        #expect(asked == ["hide", "note", "hide", "note"])
    }
}
