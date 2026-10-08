//
//  CheckpointsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
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
