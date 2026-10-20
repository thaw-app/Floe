//
//  FileIndexServiceTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreServices
import FendCore
@testable import Floe
import Foundation
import Synchronization
import Testing

/// A folder of its own in the temporary folder, and file system events that only a test sends.
private final class IndexFixture: Sendable {
    let root: URL
    /// Where a service that saves keeps its index: beside the folder, never in it.
    let saved: URL
    private let deliver = Mutex<(@Sendable ([FileIndexChange], UInt64) -> Void)?>(nil)
    private let stops = Mutex(0)
    private let asked = Mutex<[UInt64?]>([])
    private let volumeName = Mutex("volume-a")

    init(files: [String]) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-index-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: DirectoryWatcher.real(folder.path))
        saved = root.appendingPathExtension("index")
        for file in files {
            try add(file)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: saved)
        try? FileManager.default.removeItem(at: FileIndexService.stampFile(for: saved))
    }

    /// The event each watch asked to start from, in the order the watches began. Nil is "from now on".
    nonisolated var sinces: [UInt64?] {
        asked.withLock(\.self)
    }

    nonisolated var volume: String {
        get { volumeName.withLock(\.self) }
        set { volumeName.withLock { $0 = newValue } }
    }

    var stopped: Int {
        stops.withLock(\.self)
    }

    var environment: FileIndexService.Environment {
        FileIndexService.Environment(root: { [root] in root.path }, watch: { [self] _, since, deliver in
            asked.withLock { $0.append(since) }
            self.deliver.withLock { $0 = deliver }
            return { self.stops.withLock { $0 += 1 } }
        })
    }

    /// The same, keeping the index in a file and saving it as soon as it changes.
    var savingEnvironment: FileIndexService.Environment {
        var environment = environment
        environment.saved = saved
        environment.volume = { [self] _ in volume }
        environment.currentEvent = { 100 }
        environment.saveDelay = 0
        return environment
    }

    func add(_ file: String) throws {
        let url = root.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    func path(_ relative: String) -> String {
        root.appendingPathComponent(relative).path
    }

    /// Hands the service events as the stream would.
    func send(_ changes: [FileIndexChange], event: UInt64 = 0) {
        deliver.withLock(\.self)?(changes, event)
    }
}

@MainActor
struct FileIndexServiceTests {
    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 2000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    @Test func theSwitchIsOffUntilTheUserTurnsItOnAndIsKeptWithTheSettings() throws {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(!settings.indexesFileNames)
        settings.indexesFileNames = true
        settings.save()
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).indexesFileNames)
        let entry = try #require(SearchIndex.staticEntries.first { $0.id == "privacy.indexesFileNames" })
        #expect(entry.title == "Fast file search")
        #expect(entry.pane == .privacy)
    }

    @Test func foregroundIndexNeverWritesOrDeletesTheResidentCache() async throws {
        let fixture = try IndexFixture(files: ["invoice.pdf"])
        let resident = FileIndexService(environment: fixture.savingEnvironment)
        resident.set(on: true)
        await resident.settled()
        let saved = try Data(contentsOf: fixture.saved)
        let stamp = try Data(contentsOf: FileIndexService.stampFile(for: fixture.saved))
        var environment = fixture.savingEnvironment
        environment.writesCache = false
        let foreground = FileIndexService(environment: environment)
        foreground.set(on: true)
        await foreground.settled()
        #expect(foreground.files(matching: "invoice")?.count == 1)
        try fixture.add("new.txt")
        fixture.send([.folder(fixture.root.path)], event: 200)
        await foreground.settled()
        foreground.set(on: false)
        #expect(try Data(contentsOf: fixture.saved) == saved)
        #expect(try Data(contentsOf: FileIndexService.stampFile(for: fixture.saved)) == stamp)
    }

    @Test func offThereIsNoIndexAndNothingIsWatched() throws {
        let fixture = try IndexFixture(files: ["invoice.pdf"])
        let service = FileIndexService(environment: fixture.environment)
        #expect(service.state == .off)
        #expect(!service.isOn)
        #expect(service.files(matching: "invoice") == nil)
        service.set(on: false)
        #expect(fixture.stopped == 0)
    }

    @Test func onItWalksTheFolderAndAnswersWithTheRowsTheFileSearchShows() async throws {
        let fixture = try IndexFixture(files: ["Documents/invoice.pdf", "Documents/Invoices/march.txt", "Library/Caches/invoice.db", "Tools/Invoicer.app/Contents/Info.plist", "node_modules/invoice/index.js", ".hidden/invoice.txt"])
        let service = FileIndexService(environment: fixture.environment)
        service.set(on: true)
        #expect(service.state != .off)
        #expect(service.isOn, "on while it is still walking")
        await service.settled()
        guard case let .ready(names, bytes) = service.state else {
            Issue.record("the walk is done, so the index is ready")
            return
        }
        #expect(names == 6, "Documents with its three entries, and Tools with the app as one entry")
        #expect(bytes > 0)

        let files = try #require(service.files(matching: "invoice"))
        #expect(files.map(\.name) == ["Invoices", "invoice.pdf"], "the app is left to the apps, and nothing in Library, node_modules or a hidden folder is listed")
        let folder = try #require(files.first)
        #expect(folder.url.path == fixture.path("Documents/Invoices"))
        #expect(folder.contentType == "public.folder")
        #expect(folder.matched == [0, 1, 2, 3, 4, 5, 6])
        let pdf = try #require(files.last)
        #expect(pdf.contentType == "com.adobe.pdf")
        #expect(pdf.displayPath == fixture.path("Documents"))
        #expect(pdf.lastUsed == nil)
        #expect(pdf.matched == [0, 1, 2, 3, 4, 5, 6])
        #expect(try #require(service.files(matching: "no-such-name-anywhere")).isEmpty)
    }

    @Test func anEventReadsItsFolderAgain() async throws {
        let fixture = try IndexFixture(files: ["notes/first.txt", "deep/a/b/old.txt"])
        let service = FileIndexService(environment: fixture.environment)
        service.set(on: true)
        await service.settled()

        try fixture.add("notes/second.txt")
        try FileManager.default.removeItem(atPath: fixture.path("notes/first.txt"))
        #expect(service.files(matching: "second")?.isEmpty == true, "nothing is read until the file system says so")
        fixture.send([.folder(fixture.path("notes") + "/")])
        await service.settled()
        #expect(service.files(matching: "second")?.map(\.name) == ["second.txt"])
        #expect(service.files(matching: "first")?.isEmpty == true)

        // Events below a folder were lost: everything under it is read again.
        try fixture.add("deep/a/b/c/new.txt")
        fixture.send([.folder(fixture.path("deep"))])
        await service.settled()
        #expect(service.files(matching: "new.txt")?.isEmpty == true)
        fixture.send([.subtree(fixture.path("deep"))])
        await service.settled()
        #expect(service.files(matching: "new.txt")?.map(\.name) == ["new.txt"])
        #expect(service.state == .ready(names: 8, bytes: service.state.bytes))
    }

    @Test func aChangedRootWalksEverythingAgain() async throws {
        let fixture = try IndexFixture(files: ["a/one.txt"])
        let service = FileIndexService(environment: fixture.environment)
        service.set(on: true)
        await service.settled()
        try fixture.add("b/c/two.txt")
        fixture.send([.everything])
        await service.settled()
        #expect(service.files(matching: "two")?.map(\.name) == ["two.txt"])
        #expect(service.state.names == 5)
    }

    @Test func switchingItOffFreesTheIndexAndStopsTheEvents() async throws {
        let fixture = try IndexFixture(files: ["invoice.pdf"])
        let service = FileIndexService(environment: fixture.environment)
        service.set(on: true)
        service.set(on: true)
        await service.settled()
        #expect(service.files(matching: "invoice")?.count == 1)

        service.set(on: false)
        #expect(service.state == .off)
        #expect(service.files(matching: "invoice") == nil)
        #expect(fixture.stopped == 1)
        // An event that was already on its way changes nothing.
        fixture.send([.everything])
        await service.settled()
        #expect(service.state == .off)

        service.set(on: true)
        await service.settled()
        #expect(service.state.names == 1)
    }

    @Test func theFirstWalkAnswersFromTheTopFoldersBeforeTheWholeWalkIsDone() async throws {
        let fixture = try IndexFixture(files: ["top.txt", "a/b/c/d/deep.txt"])
        let service = FileIndexService(environment: fixture.environment)
        var told: [FileIndexService.State] = []
        service.observe { told.append($0) }
        service.set(on: true)
        await service.settled()
        await waitFor("both walks") { told.count == 4 }
        #expect(told.prefix(2) == [.off, .building])
        #expect(told.dropFirst(2).map(\.names) == [4, 6], "top.txt and the folders a, b and c first; then d and the file in it")
    }

    // MARK: The saved index

    @Test func aLaterLaunchIsReadyFromTheSavedIndexAndReadsOnlyWhatChangedSince() async throws {
        let fixture = try IndexFixture(files: ["docs/first.txt"])
        let first = FileIndexService(environment: fixture.savingEnvironment)
        first.set(on: true)
        await first.settled()
        #expect(fixture.sinces == [nil], "nothing is saved yet, so events are wanted from now on")
        #expect(FileManager.default.fileExists(atPath: fixture.saved.path))

        try fixture.add("docs/second.txt")
        let second = FileIndexService(environment: fixture.savingEnvironment)
        second.set(on: true)
        await second.settled()
        #expect(second.state.names == 2, "the folder and the file in it")
        #expect(second.files(matching: "first")?.map(\.name) == ["first.txt"])
        #expect(second.files(matching: "second")?.isEmpty == true, "the folder is not walked again")
        #expect(fixture.sinces == [nil, 100], "the events since the walk began are asked for")

        fixture.send([.folder(fixture.path("docs"))], event: 150)
        await second.settled()
        #expect(second.files(matching: "second")?.map(\.name) == ["second.txt"])

        let third = FileIndexService(environment: fixture.savingEnvironment)
        third.set(on: true)
        await third.settled()
        #expect(third.files(matching: "second")?.map(\.name) == ["second.txt"], "what the events brought in was saved too")
        #expect(fixture.sinces.last == 150)
    }

    @Test func changesWaitForTheDueSaveOrTheFlushAtQuit() async throws {
        let fixture = try IndexFixture(files: ["docs/first.txt"])
        var environment = fixture.savingEnvironment
        environment.saveDelay = 3600
        let service = FileIndexService(environment: environment)
        service.set(on: true)
        await service.settled()
        let walked = try Data(contentsOf: fixture.saved)

        try fixture.add("docs/second.txt")
        fixture.send([.folder(fixture.path("docs"))], event: 150)
        try fixture.add("docs/third.txt")
        fixture.send([.folder(fixture.path("docs"))], event: 160)
        await service.settled()
        #expect(try Data(contentsOf: fixture.saved) == walked, "a change does not rewrite the whole index at once")

        service.flush()
        let reopened = FileIndexService(environment: fixture.savingEnvironment)
        reopened.set(on: true)
        await reopened.settled()
        #expect(reopened.files(matching: "third")?.map(\.name) == ["third.txt"], "the flush saved every change")
        #expect(fixture.sinces.last == 160)
    }

    @Test func historicalEventsDeliveredWhenWatchingStartsAreAppliedAfterLoading() async throws {
        let fixture = try IndexFixture(files: ["first.txt"])
        let first = FileIndexService(environment: fixture.savingEnvironment)
        first.set(on: true)
        await first.settled()
        try fixture.add("second.txt")

        var environment = fixture.savingEnvironment
        environment.watch = { root, _, deliver in
            deliver([.folder(root)], 150)
            return {}
        }
        let second = FileIndexService(environment: environment)
        second.set(on: true)
        await second.settled()
        // Also drain the replay queued during initialization.
        await second.settled()
        #expect(second.files(matching: "second")?.map(\.name) == ["second.txt"])
    }

    @Test func switchingOffDuringASaveDoesNotLeaveTheCacheBehind() async throws {
        let fixture = try IndexFixture(files: ["private.txt"])
        let holder = Mutex<FileIndexService?>(nil)
        var environment = fixture.savingEnvironment
        environment.volume = { _ in
            holder.withLock { $0 }?.set(on: false)
            return "volume-a"
        }
        let service = FileIndexService(environment: environment)
        holder.withLock { $0 = service }
        defer { holder.withLock { $0 = nil } }
        service.set(on: true)
        await service.settled()
        await service.settled()
        #expect(service.state == .off)
        #expect(FileManager.default.fileExists(atPath: fixture.saved.path) == false)
        #expect(FileManager.default.fileExists(atPath: FileIndexService.stampFile(for: fixture.saved).path) == false)
    }

    @Test func startingTheIndexReadsItsRootAndStampOffTheMainThread() async throws {
        let fixture = try IndexFixture(files: ["first.txt"])
        let first = FileIndexService(environment: fixture.savingEnvironment)
        first.set(on: true)
        await first.settled()
        var environment = fixture.savingEnvironment
        environment.root = { [root = fixture.root] in
            #expect(Thread.isMainThread == false)
            return root.path
        }
        environment.volume = { _ in
            #expect(Thread.isMainThread == false)
            return "volume-a"
        }
        let second = FileIndexService(environment: environment)
        second.set(on: true)
        await second.settled()
        #expect(second.files(matching: "first")?.count == 1)
    }

    @Test func aSavedIndexFromAnotherVolumeOrADamagedOneIsWalkedAgain() async throws {
        let fixture = try IndexFixture(files: ["early.txt"])
        let first = FileIndexService(environment: fixture.savingEnvironment)
        first.set(on: true)
        await first.settled()

        // Events are numbered per volume: on another one the saved number means nothing.
        try fixture.add("late.txt")
        fixture.volume = "volume-b"
        let second = FileIndexService(environment: fixture.savingEnvironment)
        second.set(on: true)
        await second.settled()
        #expect(second.files(matching: "late")?.map(\.name) == ["late.txt"])
        #expect(fixture.sinces == [nil, nil])

        try Data("not an index".utf8).write(to: fixture.saved)
        try fixture.add("later.txt")
        let third = FileIndexService(environment: fixture.savingEnvironment)
        third.set(on: true)
        await third.settled()
        #expect(third.files(matching: "later")?.map(\.name) == ["later.txt"])
        #expect(fixture.sinces.last == 100, "the stamp was good, so the events since are asked for even though the file was not")
    }

    @Test func switchingItOffRemovesTheSavedIndex() async throws {
        let fixture = try IndexFixture(files: ["invoice.pdf"])
        let service = FileIndexService(environment: fixture.savingEnvironment)
        service.set(on: true)
        await service.settled()
        let stamp = FileIndexService.stampFile(for: fixture.saved)
        #expect(FileManager.default.fileExists(atPath: fixture.saved.path))
        #expect(FileManager.default.fileExists(atPath: stamp.path))

        service.set(on: false)
        await service.settled()
        #expect(!FileManager.default.fileExists(atPath: fixture.saved.path), "the names of the user's files do not outlive the switch")
        #expect(!FileManager.default.fileExists(atPath: stamp.path))
    }

    @Test func withoutAFileToSaveToNothingIsWritten() async throws {
        let fixture = try IndexFixture(files: ["a.txt"])
        let service = FileIndexService(environment: fixture.environment)
        service.set(on: true)
        await service.settled()
        #expect(!FileManager.default.fileExists(atPath: fixture.saved.path))
    }

    @Test func eachNewStateIsToldOnTheMainThread() async throws {
        let fixture = try IndexFixture(files: ["a.txt"])
        let service = FileIndexService(environment: fixture.environment)
        var told: [FileIndexService.State] = []
        service.observe { told.append($0) }
        service.set(on: true)
        await service.settled()
        await waitFor("ready") { told.count == 3 }
        #expect(told.prefix(2) == [.off, .building])
        #expect(told.last?.names == 1)
        service.set(on: false)
        await waitFor("off") { told.last == .off }
        #expect(told.count == 4)
    }

    @Test func theStateCrossesToTheSettingsProcessAsText() {
        for state in [FileIndexService.State.off, .building, .ready(names: 471_000, bytes: 60_000_000), .ready(names: 0, bytes: 0)] {
            #expect(FileIndexService.State(text: state.text) == state)
        }
        #expect(FileIndexService.State.ready(names: 12, bytes: 34).text == "ready 12 34")
        for text in ["", "ready", "ready 1", "ready a 2", "ready 1 -2", "ready 1 2 3", "off now", "gone"] {
            #expect(FileIndexService.State(text: text) == nil, "\(text)")
        }
    }

    @Test func thePrivacyPageSaysWhatTheIndexHolds() {
        #expect(FileIndexService.State.off.line == nil)
        #expect(FileIndexService.State.building.line == "Reading the names of your files…")
        let size = ByteCountFormatter.string(fromByteCount: 60_000_000, countStyle: .memory)
        #expect(FileIndexService.State.ready(names: 471_000, bytes: 60_000_000).line == "471,000 names, \(size)")
        #expect(FileIndexService.State.ready(names: 1, bytes: 60_000_000).line == "1 name, \(size)")
    }

    @Test func theFixedExclusionsAreTheOnesThePrivacyPageDescribes() {
        #expect(FileIndexService.excludedNames == ["Library", "node_modules", ".git", ".Trash", ".build", "target", "DerivedData", ".cache", "Pods", ".npm", ".cargo", ".rustup"])
        #expect(FileIndexService.packageSuffixes.contains(".app") && FileIndexService.packageSuffixes.contains(".photoslibrary"))
        #expect(FileIndexService.packageSuffixes.contains(".noindex"), "a folder that asks not to be indexed is one entry")
        let hit = FileIndex.Hit(path: "/Users/someone/Projects/Library/notes.txt", isFolder: false, score: 1, matched: [])
        #expect(FileIndexService.result(for: hit, home: "/Users/someone") == nil, "as the Spotlight search leaves it out")
        let plain = FileIndex.Hit(path: "/Users/someone/Projects/notes", isFolder: false, score: 1, matched: [2])
        let result = FileIndexService.result(for: plain, home: "/Users/someone")
        #expect(result?.displayPath == "~/Projects")
        #expect(result?.contentType == nil)
        #expect(result?.matched == [2])
    }

    @Test func aFileOpenedLatelyLeadsOneThatScoresALittleHigher() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hit = { (name: String, score: Int) in FileIndex.Hit(path: "/Users/someone/\(name)", isFolder: false, score: score, matched: []) }
        let hits = [hit("best", 120), hit("opened today", 100), hit("opened long ago", 100), hit("never opened", 100), hit("weak but opened today", 60)]
        let used = [
            "/Users/someone/opened today": now.addingTimeInterval(-3600),
            "/Users/someone/opened long ago": now.addingTimeInterval(-29 * 24 * 3600),
            "/Users/someone/weak but opened today": now,
        ]
        let ranked = FileIndexService.ranked(hits, lastUsed: { used[$0] }, now: now)
        let names = ranked.map { URL(fileURLWithPath: $0.hit.path).lastPathComponent }
        #expect(names == ["opened today", "best", "opened long ago", "never opened", "weak but opened today"])
        #expect(ranked.first?.lastUsed == now.addingTimeInterval(-3600))
        #expect(ranked[1].lastUsed == nil)

        let untouched = FileIndexService.ranked(hits, lastUsed: { _ in nil }, now: now)
        #expect(untouched.map(\.hit) == hits, "with nothing opened the index's own order stands")
        let result = FileIndexService.result(for: hits[1], home: "/Users/someone", lastUsed: now)
        #expect(result?.lastUsed == now)
    }

    @Test func theEventsLeaveOutTheFoldersTheIndexNeverLists() {
        let excluded = FileIndexEvents.excludedPaths(under: "/Users/someone")
        #expect(excluded.first == "/Users/someone/Library")
        #expect(excluded.count <= 8, "the system takes eight at most")
        let names = excluded.map { URL(fileURLWithPath: $0).lastPathComponent }
        #expect(names.filter { !FileIndexService.excludedNames.contains($0) } == [], "each is a folder the index skips")
    }
}

@MainActor
struct FileIndexEventTests {
    private func flags(_ values: Int...) -> [FSEventStreamEventFlags] {
        values.map { FSEventStreamEventFlags($0) }
    }

    @Test func anEventNamesTheFolderToReadAgain() {
        let changes = FileIndexEvents.changes(paths: ["/home/a/", "/home/b/", "/home/a/"], flags: flags(0, kFSEventStreamEventFlagItemCreated, 0))
        #expect(changes == [.folder("/home/a/"), .folder("/home/b/")], "each folder once")
    }

    @Test func lostEventsReadTheSubtreeAgain() {
        let lost = [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped, kFSEventStreamEventFlagKernelDropped]
        for flag in lost {
            #expect(FileIndexEvents.changes(paths: ["/home/a/"], flags: flags(flag)) == [.subtree("/home/a/")])
        }
    }

    @Test func aChangedRootAsksForEverything() {
        let changes = FileIndexEvents.changes(paths: ["/home/a/", "/home", "/home/b/"], flags: flags(0, kFSEventStreamEventFlagRootChanged, 0))
        #expect(changes == [.everything])
    }

    @Test func eventsThatAreNotAboutFoldersAreLeftOut() {
        let changes = FileIndexEvents.changes(paths: ["/home", "/Volumes/Disk", "/Volumes/Disk"], flags: flags(kFSEventStreamEventFlagHistoryDone, kFSEventStreamEventFlagMount, kFSEventStreamEventFlagUnmount))
        #expect(changes.isEmpty)
        #expect(FileIndexEvents.changes(paths: [], flags: []).isEmpty)
    }
}

@MainActor
struct FileSearchIndexTests {
    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 2000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func ready(_ fixture: IndexFixture) async -> FileIndexService {
        let service = FileIndexService(environment: fixture.environment)
        service.set(on: true)
        await service.settled()
        return service
    }

    @Test func onlyATypedQueryIsAskedOfTheIndex() {
        #expect(FileSearch.asksIndex("inv", isOn: true), "asked, and Spotlight answers when the index says it is not built")
        #expect(!FileSearch.asksIndex("inv", isOn: false))
        #expect(!FileSearch.asksIndex("", isOn: true), "the recent files come from Spotlight")
        #expect(!FileSearch.asksIndex("  ", isOn: true))
    }

    @Test func theFileSearchShowsWhatTheIndexFindsAtEachKey() async throws {
        let fixture = try IndexFixture(files: ["Documents/invoice.pdf", "Documents/inventory.txt"])
        let model = await FileSearchModel(index: ready(fixture))
        defer { model.cancel() }
        model.query = "inv"
        await waitFor("both files") { model.spotlight.results.count == 2 }
        model.query = "invoi"
        await waitFor("one file") { model.spotlight.results.count == 1 }
        #expect(model.selectedFile?.name == "invoice.pdf")
        #expect(model.selectedFile?.matched == [0, 1, 2, 3, 4])
        #expect(!model.spotlight.isSearching)
    }

    @Test func anAnswerForAQueryThatWasTypedPastIsDropped() async throws {
        let fixture = try IndexFixture(files: ["invoice.pdf", "letter.txt"])
        let search = await FileSearch(index: ready(fixture))
        search.search("invoice")
        search.search("letter")
        await waitFor("the newest query") { search.results.map(\.name) == ["letter.txt"] }
        search.search("invoice")
        search.cancel()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(search.results.isEmpty, "cancelled before its answer came")
    }

    @Test func theFilesScopeAndSourceListWhatTheIndexFinds() async throws {
        let fixture = try IndexFixture(files: ["Documents/invoice.pdf", "Documents/invoice-2.pdf"])
        let scope = await FileSearchScope(index: ready(fixture))
        var batches: [[String]] = []
        let updates = try #require(scope.updates(for: "invoice", context: SearchContext(query: "files invoice")))
        for await batch in updates {
            batches.append(batch.map(\.title))
        }
        #expect(batches == [["invoice.pdf", "invoice-2.pdf"]], "one answer, and the stream ends with it")

        let inline = try #require(scope.inlineUpdates(for: "invoice-2", context: SearchContext(query: "invoice-2")))
        var rows: [RootItem] = []
        for await batch in inline {
            rows = batch
        }
        #expect(rows.map(\.title) == ["invoice-2.pdf"])
    }
}

private extension FileIndexService.State {
    var names: Int? {
        if case let .ready(names, _) = self {
            names
        } else {
            nil
        }
    }

    var bytes: Int {
        if case let .ready(_, bytes) = self {
            bytes
        } else {
            0
        }
    }
}
