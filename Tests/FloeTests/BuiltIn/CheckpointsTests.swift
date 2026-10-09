//
//  CheckpointsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

@MainActor
struct CheckpointsTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-checkpoints-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func tab(_ browser: BrowserApp, window: String, _ title: String, _ url: String) -> BrowserTab {
        BrowserTab(browser: browser, window: window, key: "1", title: title, url: url)
    }

    private func model(in folder: URL) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-checkpoints-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        return model
    }

    @Test(arguments: [
        ("pause website redesign", "website redesign", ""),
        ("Pause  taxes : call the accountant", "taxes", "call the accountant"),
        ("pause a: b: c", "a", "b: c"),
    ])
    func theKeywordANameAndANoteAfterAColon(query: String, name: String, note: String) {
        let request = Checkpoint.request(in: query)
        #expect(request?.name == name)
        #expect(request?.note == note)
    }

    @Test(arguments: ["pause", "pause ", "pause : only a note", "paused work", "resume taxes"])
    func anythingElseIsAnOrdinarySearch(query: String) {
        #expect(Checkpoint.request(in: query) == nil)
    }

    @Test func onlyTheTabsOfTheWindowInFrontAreKeptForEachBrowser() {
        let tabs = [
            tab(.safari, window: "10", "Docs", "https://example.com/docs"),
            tab(.safari, window: "10", "Issue", "https://example.com/issue"),
            tab(.safari, window: "11", "Mail", "https://mail.example.com"),
            tab(.helium, window: "7", "Preview", "http://localhost:3000"),
            tab(.helium, window: "8", "News", "https://news.example.com"),
        ]
        #expect(Checkpoint.frontWindowTabs(tabs).map(\.title) == ["Docs", "Issue", "Preview"])
        let many = (0 ..< 80).map { tab(.safari, window: "1", "Tab \($0)", "https://example.com/\($0)") }
        #expect(Checkpoint.frontWindowTabs(many).count == Checkpoint.tabLimit)

        let items = Checkpoint.items(files: [URL(fileURLWithPath: "/Users/me/site/index.html")], tabs: tabs + [tab(.safari, window: "10", "Blank", "")])
        #expect(items.map(\.kind) == [.file, .link, .link, .link])
        #expect(items.first?.title == "index.html")
        #expect(!items.contains { $0.value.isEmpty }, "a tab with no address is not something to come back to")
    }

    @Test func aCheckpointSaysWhatItHoldsAndWhatIsMissing() {
        let checkpoint = Checkpoint(
            name: "site", note: "fix the nav",
            items: [
                .init(kind: .file, value: "/here/index.html", title: "index.html"),
                .init(kind: .file, value: "/gone/old.css", title: "old.css"),
                .init(kind: .link, value: "https://example.com", title: "Example"),
            ],
            saved: Date(timeIntervalSince1970: 0)
        )
        #expect(checkpoint.summary == "2 files and 1 tab")
        #expect(Checkpoint(name: "n", note: "x", items: [], saved: Date()).summary == "a note")
        #expect(Checkpoint(name: "n", note: "", items: [checkpoint.items[2]], saved: Date()).summary == "1 tab")
        let exists: (String) -> Bool = { $0.hasPrefix("/here") }
        #expect(checkpoint.missing(exists: exists).map(\.title) == ["old.css"])
        let details = checkpoint.details(exists: exists)
        #expect(details.contains("fix the nav"))
        #expect(details.contains("Missing: /gone/old.css"))
        #expect(details.contains("\n/here/index.html"))
        #expect(details.hasSuffix("https://example.com"))
    }

    @Test func aCheckpointOfTheSameNameIsReplacedAndOneCanBeDeleted() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        #expect(store.all.isEmpty)
        store.save(Checkpoint(name: "Site", note: "first", items: [], saved: Date()))
        store.save(Checkpoint(name: "taxes", note: "", items: [], saved: Date()))
        store.save(Checkpoint(name: "site", note: "second", items: [], saved: Date()))
        #expect(store.all.map(\.name) == ["site", "taxes"], "the newer state of the same task, newest first")
        #expect(store.all.first?.note == "second")
        try store.delete(#require(store.all.last).id)
        #expect(CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json")).all.map(\.name) == ["site"])
    }

    @Test func pauseSavesWhatIsSelectedAndTheFrontTabsAndTheSearchFindsItByName() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        let front = [tab(.safari, window: "1", "Docs", "https://example.com/docs")]
        model.checkpointing.finderItems = { [URL(fileURLWithPath: "/Users/me/site")] }
        model.checkpointing.tabs = { front }

        model.query = "pause website redesign: fix the nav"
        let draft = try #require(model.results.first?.item)
        #expect(draft.title == "Save Checkpoint “website redesign”")
        #expect(model.primaryActionTitle(for: draft) == "Save")
        await model.saveCheckpoint(named: "website redesign", note: "fix the nav").value
        #expect(said == ["Saved website redesign: 1 file and 1 tab"])
        #expect(model.checkpointStore.all.map(\.name) == ["website redesign"])

        model.query = "website"
        let row = try #require(model.results.first { $0.item.kind == "Checkpoint" }?.item)
        #expect(row.title == "Resume website redesign")
        #expect(row.rowLabel == "1 file and 1 tab")
        #expect(model.primaryActionTitle(for: row) == "Resume")
        #expect(model.rootActions(for: row).compactMap { $0?.title }.prefix(5) == ["Resume", "Show Details", "Save Again", "Copy Note", "Delete Checkpoint…"])
        model.query = ""
        #expect(!model.results.contains { $0.item.kind == "Checkpoint" }, "found by searching, not listed among the apps")
    }

    @Test func savingReadsFinderOffTheMainThread() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        let log = ThreadLog()
        model.checkpointing.finderItems = {
            log.note("finder")
            return []
        }
        model.checkpointing.tabs = { [] }
        await model.saveCheckpoint(named: "thought", note: "call the bank").value
        #expect(log.onMain == ["finder": false])
        #expect(model.checkpointStore.all.map(\.name) == ["thought"])
    }

    @Test func nothingSelectedNoBrowserAndNoNoteSavesNothing() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        model.checkpointing.finderItems = { [] }
        model.checkpointing.tabs = { [] }
        await model.saveCheckpoint(named: "empty", note: "").value
        #expect(model.checkpointStore.all.isEmpty)
        #expect(said.first?.hasPrefix("Nothing to save.") == true)
        await model.saveCheckpoint(named: "thought", note: "call the bank").value
        #expect(model.checkpointStore.all.map(\.summary) == ["a note"], "a note alone is worth keeping")
    }

    @Test func resumeOpensWhatIsThereAndSaysWhatIsGone() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var opened: [String] = []
        model.checkpointing.openFile = { opened.append($0.path) }
        var shown: [String] = []
        model.shell.showOutput = { title, text in shown.append("\(title)|\(text.contains("Missing: "))") }
        let here = folder.appendingPathComponent("index.html")
        try Data().write(to: here)

        let whole = Checkpoint(name: "site", note: "fix the nav", items: [.init(kind: .file, value: here.path, title: "index.html")], saved: Date())
        model.resume(whole)
        #expect(opened == [here.path])
        #expect(said == ["fix the nav"], "the note of the next step is what is said")
        #expect(shown.isEmpty)

        let broken = Checkpoint(
            name: "old", note: "",
            items: [.init(kind: .file, value: here.path, title: "index.html"), .init(kind: .file, value: folder.appendingPathComponent("gone.css").path, title: "gone.css")],
            saved: Date()
        )
        model.resume(broken)
        #expect(opened == [here.path, here.path], "what is there still opens")
        #expect(said.last == "1 of 2 are missing")
        #expect(shown == ["old|true"], "and the list says which")
    }

    // MARK: The preferred apps

    private var zed: ResolvedApp {
        ResolvedApp(url: URL(fileURLWithPath: "/Applications/Zed.app"))
    }

    /// A Mac that has the app with that bundle identifier, or none at all.
    private func lookup(installed identifier: String?) -> AppLookup {
        AppLookup(url: { [zed] in $0 == identifier ? zed.url : nil }, plainTextApp: { nil }, exists: { _ in false }, bundleIdentifier: { _ in nil })
    }

    @Test(arguments: [
        ("main.swift", true), ("notes.md", true), ("readme.txt", true), ("page.html", true), ("data.json", true),
        ("photo.png", false), ("invoice.pdf", false), ("song.mp3", false), ("archive.zip", false), ("Floe.app", false),
    ])
    func theEditorIsHandedTextAndCodeAndNothingElse(name: String, toEditor: Bool) {
        let file = URL(fileURLWithPath: "/nowhere/\(name)")
        let handoff = Checkpoint.editorHandoff(for: file, editor: zed) { _ in false }
        #expect(handoff == (toEditor ? Handoff(urls: [file], application: zed.url) : nil))
        #expect(Checkpoint.editorHandoff(for: file, editor: nil) { _ in false } == nil, "with no editor chosen every file is its own app's")
    }

    @Test func aFolderIsNeverTheEditorsEvenWhenItsNameReadsAsCode() {
        let folder = URL(fileURLWithPath: "/nowhere/site.swift")
        #expect(Checkpoint.editorHandoff(for: folder, editor: zed, isFolder: { _ in true }, isText: { _ in true }) == nil)
        #expect(Checkpoint.editorHandoff(for: folder, editor: zed, isFolder: { _ in false }, isText: { _ in true }) != nil)
    }

    /// A checkpoint of a folder, two text files, a picture and a tab, all there, and what resuming it opened where.
    private func resumed(in folder: URL, editor: AppChoice?, installed: String?) throws -> (editor: [String], own: [String], links: [String]) {
        let model = model(in: folder)
        model.settings.editorApp = editor
        model.appLookup = lookup(installed: installed)
        var editor: [String] = []
        var own: [String] = []
        let links = Mutex<[String]>([])
        model.checkpointing.openFile = { own.append($0.lastPathComponent) }
        model.checkpointing.openIn = { handoff in editor += handoff.urls.map { "\($0.lastPathComponent) in \(handoff.application.lastPathComponent)" } }
        model.linkOpener = LinkOpener { url, _ in links.withLock { $0.append(url.absoluteString) } }
        let site = folder.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        let names = ["main.swift", "notes.md", "photo.png"]
        for name in names {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let files = ([site] + names.map(folder.appendingPathComponent)).map { Checkpoint.Item(kind: .file, value: $0.path, title: $0.lastPathComponent) }
        model.resume(Checkpoint(name: "site", note: "", items: files + [.init(kind: .link, value: "https://example.com/docs", title: "Docs")], saved: Date()))
        return (editor, own, links.withLock { $0 })
    }

    @Test func resumeOpensTextAndCodeInTheChosenEditorFoldersInFinderAndTheRestInTheirApps() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let opened = try resumed(in: folder, editor: AppChoice(bundleIdentifier: "dev.zed.Zed", path: "/Applications/Zed.app"), installed: "dev.zed.Zed")
        #expect(opened.editor == ["main.swift in Zed.app", "notes.md in Zed.app"])
        #expect(opened.own == ["site", "photo.png"], "a folder goes to Finder and a picture to its own app")
        #expect(opened.links == ["https://example.com/docs"])
    }

    @Test func withNoEditorChosenOrOneThatIsGoneEveryFileOpensInItsOwnApp() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let none = try resumed(in: folder.appendingPathComponent("none"), editor: nil, installed: "dev.zed.Zed")
        #expect(none.editor.isEmpty)
        #expect(none.own == ["site", "main.swift", "notes.md", "photo.png"])
        let gone = try resumed(in: folder.appendingPathComponent("gone"), editor: AppChoice(bundleIdentifier: "dev.zed.Zed", path: "/Applications/Zed.app"), installed: nil)
        #expect(gone.editor.isEmpty, "the stand-in for a missing editor is what text files open in anyway")
        #expect(gone.own == ["site", "main.swift", "notes.md", "photo.png"])
    }

    @Test func deletingAsksFirstAndLeavesTheFilesAlone() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model(in: folder)
        let checkpoint = Checkpoint(name: "site", note: "", items: [], saved: Date())
        model.checkpointStore.save(checkpoint)
        model.reloadCheckpoints()
        let delete = try #require(model.checkpointActions(checkpoint).last ?? nil)
        model.checkpointing.confirmsDelete = { _ in false }
        delete.run()
        #expect(model.checkpointStore.all.count == 1)
        model.checkpointing.confirmsDelete = { _ in true }
        delete.run()
        #expect(model.checkpointStore.all.isEmpty)
        #expect(model.checkpoints.isEmpty)
    }
}
