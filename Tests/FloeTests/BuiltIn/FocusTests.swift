//
//  FocusTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// What stands in for the Shortcuts tool and for opening an app: the runs asked for, with the text each was given.
private final nonisolated class Stand: Sendable {
    struct Run: Equatable {
        var arguments: [String]
        var input: String?
    }

    struct State {
        var runs: [Run] = []
        var answer = ShortcutsToolResult(succeeded: true)
        var opened: [String] = []
        var files: [String] = []
    }

    let state = Mutex(State())

    /// Reads the input file while it is there: the tool's caller deletes it when the run ends.
    var tool: ShortcutsTool {
        ShortcutsTool { [self] arguments in
            let file = arguments.firstIndex(of: "--input-path").map { arguments[$0 + 1] }
            let input = file.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            return state.withLock {
                $0.files += [file].compactMap(\.self)
                $0.runs.append(Run(arguments: arguments.map { $0 == file ? "<input>" : $0 }, input: input))
                return $0.answer
            }
        }
    }

    var opener: LinkOpener {
        LinkOpener { [self] url, _ in state.withLock { $0.opened.append(url.path) } }
    }

    var runs: [Run] {
        state.withLock { $0.runs }
    }

    var opened: [String] {
        state.withLock { $0.opened }
    }
}

@MainActor
struct FocusTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A model whose Shortcuts tool and link opener are the stand-in, with that Shortcut named in its settings.
    private func model(in folder: URL, stand: Stand, shortcut: String) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-focus-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.focusShortcut = shortcut
        let model = LauncherModel(settings: settings, usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.shortcutLibrary.tool = stand.tool
        model.linkOpener = stand.opener
        return model
    }

    // MARK: Reading the words

    @Test(arguments: [
        ("focus 1 hour", "60"), ("focus 25m", "25"), ("Focus  1h 30m", "90"), ("focus 45", "45"), ("focus 90s", "2"),
        ("focus 30 seconds", "1"), ("focus 24h", "1440"), ("focus off", "off"), ("FOCUS OFF", "off"), ("focus 1.5h", "90"),
    ])
    func theWordAndALengthOrOff(query: String, input: String) {
        #expect(FocusRequest.request(in: query)?.input == input)
    }

    @Test(arguments: ["focus", "focus ", "focus on work", "focus 0", "focus 0m", "focus 25h", "focus 20m deep work", "focus offline", "focus on", "focused 1h", "refocus off"])
    func anythingElseIsAnOrdinarySearch(query: String) {
        #expect(FocusRequest.request(in: query) == nil)
        #expect(FocusSearchProvider().contribution(for: SearchContext(query: query)).pinned.isEmpty)
    }

    @Test func whatTheShortcutReceivesIsMinutesOrAWord() {
        #expect(FocusRequest.toggle.input == "toggle")
        #expect(FocusRequest(change: .off).input == "off")
        #expect(FocusRequest(change: .minutes(60)).input == "60")
        #expect(FocusRequest.request(in: "focus 1 hour") == FocusRequest(change: .minutes(60)))
        #expect(ShortcutsTool.arguments(running: "Set Focus", inputFile: "/tmp/in.txt") == ["run", "--input-path", "/tmp/in.txt", "--", "Set Focus"])
        #expect(ShortcutsTool.arguments(running: "-quiet", inputFile: "/tmp/in.txt").suffix(2) == ["--", "-quiet"], "a name that starts with a hyphen is not an option")
    }

    // MARK: The rows

    @Test func theRowsSayWhatIsAskedAndWhichShortcutRuns() {
        let toggle = RootItem.focus(.toggle, shortcut: "Set Focus")
        #expect(toggle.title == "Toggle Focus")
        #expect(toggle.rowLabel == "Set Focus")
        #expect(toggle.kind == "Focus")
        #expect(toggle.id == "focus-toggle")
        #expect(toggle.settingsKey == "focus-toggle")
        #expect(!toggle.isScopeResult)
        #expect(LauncherModel.keepsItsPlace(toggle), "the command is there every time")
        #expect(toggle.keywords == ["focus", "do not disturb", "dnd", "quiet", "silence notifications"])

        let hour = RootItem.focus(FocusRequest(change: .minutes(60)), shortcut: "")
        #expect(hour.title == "Focus for \(TimeLength.text(3600))")
        #expect(hour.rowLabel == "No Shortcut named in Settings")
        #expect(hour.id == "focus-request")
        #expect(hour.settingsKey == nil)
        #expect(hour.isScopeResult)
        #expect(!LauncherModel.keepsItsPlace(hour), "a length being typed is not something to favorite")
        #expect(RootItem.focus(FocusRequest(change: .off), shortcut: "").title == "Turn Focus Off")
    }

    @Test func toggleFocusIsFoundByWhatPeopleCallItAndTheTypedRowLeads() {
        var context = SearchContext(query: "do not disturb")
        context.focusShortcut = "  Set Focus "
        let found = RootSearch.results(for: context)
        #expect(found.first?.id == "focus-toggle")
        #expect(found.first?.item.rowLabel == "Set Focus", "the name is read without the spaces around it")
        #expect(RootSearch.results(for: SearchContext(query: "dnd")).first?.id == "focus-toggle")
        #expect(RootSearch.results(for: SearchContext(query: "toggle focus")).first?.id == "focus-toggle")
        #expect(RootSearch.results(for: SearchContext(query: "")).contains { $0.id == "focus-toggle" })

        let typed = RootSearch.results(for: SearchContext(query: "focus 1 hour"))
        #expect(typed.first?.id == "focus-request")
        #expect(typed.first?.item.rowLabel == "No Shortcut named in Settings")
        #expect(RootSearch.results(for: SearchContext(query: "focus")).first?.id == "focus-toggle")
    }

    // MARK: Return

    @Test func returnRunsTheNamedShortcutWithTheMinutesAsItsInput() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand, shortcut: "Set Focus")
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "focus 1 hour"
        let row = try #require(model.results.first?.item)
        #expect(row.title == "Focus for \(TimeLength.text(3600))")
        #expect(row.rowLabel == "Set Focus")
        #expect(model.primaryActionTitle(for: row) == "Run Shortcut")
        guard case let .focus(request, shortcut) = row else {
            Issue.record("the row is not a Focus row")
            return
        }
        model.activate(row)
        #expect(hidden == 1)
        #expect(model.query.isEmpty)
        for _ in 0 ..< 200 where stand.runs.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(stand.runs.map(\.input) == ["60"])

        await model.setFocus(request, shortcut: shortcut)?.value
        await model.setFocus(FocusRequest(change: .off), shortcut: shortcut)?.value
        await model.setFocus(.toggle, shortcut: shortcut)?.value
        let run = ["run", "--input-path", "<input>", "--", "Set Focus"]
        #expect(stand.runs.suffix(3) == [.init(arguments: run, input: "60"), .init(arguments: run, input: "off"), .init(arguments: run, input: "toggle")])
        #expect(said.isEmpty, "only a failure is heard of")
        #expect(stand.opened.isEmpty)
        #expect(model.receipts.all.isEmpty)
        let files = stand.state.withLock { $0.files }
        #expect(files.count == 4)
        #expect(!files.suffix(3).contains { FileManager.default.fileExists(atPath: $0) }, "each input file is gone once its run ends")
    }

    @Test func toggleFocusRunsTheShortcutWithTheWordToggle() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand, shortcut: "Set Focus")
        model.query = "toggle focus"
        let row = try #require(model.results.first?.item)
        #expect(row.id == "focus-toggle")
        #expect(model.primaryActionTitle(for: row) == "Run Shortcut")
        #expect(model.rootActions(for: row).compactMap { $0?.title } == ["Run Shortcut", "Add to Favorites", "Hide from Search"])
        model.activate(row)
        for _ in 0 ..< 200 where stand.runs.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(stand.runs == [.init(arguments: ["run", "--input-path", "<input>", "--", "Set Focus"], input: "toggle")])
    }

    @Test func aShortcutThatFailsIsSaidToHave() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.state.withLock { $0.answer = ShortcutsToolResult(succeeded: false, errorOutput: "Error: The shortcut “Set Focus” could not be found.\n") }
        let model = model(in: folder, stand: stand, shortcut: "Set Focus")
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.setFocus(.toggle, shortcut: "Set Focus")?.value
        #expect(said == ["Set Focus failed: Error: The shortcut “Set Focus” could not be found."])

        stand.state.withLock { $0.answer = ShortcutsToolResult(succeeded: false) }
        await model.setFocus(.toggle, shortcut: "Set Focus")?.value
        #expect(said.last == "Set Focus failed. Open it in Shortcuts to see why.")
    }

    @Test func withNoShortcutNamedTheRowSaysSoAndReturnOpensShortcuts() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand, shortcut: "")
        var said: [String] = []
        model.showHUD = { said.append($0) }

        model.query = "focus off"
        let row = try #require(model.results.first?.item)
        #expect(row.title == "Turn Focus Off")
        #expect(row.rowLabel == "No Shortcut named in Settings")
        #expect(model.primaryActionTitle(for: row) == "Open Shortcuts")
        model.activate(row)
        #expect(stand.opened == ["/System/Applications/Shortcuts.app"])
        #expect(said == ["Make a Shortcut that sets your Focus, then name it in Settings › General"])
        #expect(stand.runs.isEmpty)

        model.query = "toggle focus"
        let toggle = try #require(model.results.first?.item)
        #expect(toggle.rowLabel == "No Shortcut named in Settings")
        #expect(model.primaryActionTitle(for: toggle) == "Open Shortcuts")
        #expect(model.setFocus(.toggle, shortcut: "") == nil)
        #expect(stand.opened.count == 2)
        #expect(stand.runs.isEmpty)
    }

    // MARK: The setting

    @Test func theShortcutsNameIsKeptWithTheSettings() throws {
        let suite = "floe-focus-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.focusShortcut.isEmpty, "none is named until the user names one")
        settings.focusShortcut = "Set Focus"
        settings.save()
        #expect(AppSettings(defaults: defaults, savesAfterEdits: false).focusShortcut == "Set Focus")

        let entry = try #require(SearchIndex.staticEntries.first { $0.id == "general.focusShortcut" })
        #expect(entry.title == "Shortcut for Focus")
        #expect(entry.pane == .general)
        #expect(entry.descriptionText?.contains("the number of minutes, the word off, or the word toggle") == true)
    }
}
