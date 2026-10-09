//
//  LauncherCatalogTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Counts started scans from any thread, so tests can wait for the worker tasks to reach the scanner.
private final nonisolated class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

/// Records the includeRaycast flags of command requests from any thread.
private final nonisolated class RaycastRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func record(_ value: Bool) {
        lock.withLock { values.append(value) }
    }

    var all: [Bool] {
        lock.withLock { values }
    }
}

/// Every scan suspends on its own gate until the test opens it, so results pair with requests
/// deterministically and nothing waits on wall-clock time.
private actor ControlledScanner: CatalogScanning {
    private var appResults: [[AppEntry]]
    private var commandResults: [[ExtensionCommand]]
    private var appGates: [Gate] = []
    private var commandGates: [Gate] = []
    nonisolated let startedScans = ScanCounter()
    /// Command scans alone, for a test that needs to know one has reached the scanner before starting the next.
    nonisolated let startedCommandScans = ScanCounter()
    nonisolated let receivedIncludeRaycast = RaycastRecorder()

    init(apps: [[AppEntry]], commands: [[ExtensionCommand]]) {
        appResults = apps
        commandResults = commands
    }

    func scanApps() async -> [AppEntry] {
        let gate = Gate()
        appGates.append(gate)
        // Taken before the wait: gates opened back to back resume in either order.
        let result = appResults.isEmpty ? [] : appResults.removeFirst()
        startedScans.increment()
        await gate.wait()
        return result
    }

    func scanCommands(includeRaycast: Bool) async -> [ExtensionCommand] {
        receivedIncludeRaycast.record(includeRaycast)
        let gate = Gate()
        commandGates.append(gate)
        let result = commandResults.isEmpty ? [] : commandResults.removeFirst()
        startedScans.increment()
        startedCommandScans.increment()
        await gate.wait()
        return result
    }

    func openAppScan(at index: Int) async {
        // The scan task registers its gate when it reaches the scanner; yielding lets that happen
        // without sleeping, and actor reentrancy keeps this from deadlocking against the scan.
        while appGates.count <= index {
            await Task.yield()
        }
        await appGates[index].open()
    }

    func openCommandScan(at index: Int) async {
        while commandGates.count <= index {
            await Task.yield()
        }
        await commandGates[index].open()
    }
}

/// Resumes every waiter when it is opened.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Fixture.app returns a RootItem; the catalog works with the bare entries.
private func appEntry(_ name: String) -> AppEntry {
    AppEntry(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
}

@MainActor
struct LauncherCatalogTests {
    private let safari = appEntry("Safari")
    private let planets = Fixture.command("planets")
    private let weather = Fixture.command("forecast", extension: "weather")

    /// The scanner's results arrive through a worker task and publish on the main actor, which takes
    /// a few real hops; this polls briefly so tests observe publications rather than task scheduling.
    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "floe-catalog-tests-\(UUID().uuidString)")!)
    }

    // MARK: Construction

    @Test func constructionStartsNoScansAndKeepsTheBuiltins() {
        let scanner = ControlledScanner(apps: [], commands: [])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        #expect(scanner.startedScans.value == 0)
        #expect(
            // Snippets come from the user's own file, and Thaw's actions and the Finder selection rows from the apps on this Mac.
            model.results.map(\.id).filter { !$0.hasPrefix("snippet:") && !$0.hasPrefix("thaw:") && !$0.hasPrefix("finder-selection:") }.sorted()
                == (["builtin:clipboard-history", "builtin:emoji-search", "builtin:file-search", "builtin:menubar-search", "focus-toggle", "note:new", "settings"]
                    + SystemCommand.allCases.map { "system:\($0.rawValue)" }).sorted(),
            "the built-ins are there before any catalog arrives"
        )
        #expect(model.isLoadingCatalog, "without a snapshot the first load is still pending")
    }

    @Test func aSnapshotWorksImmediatelyAndStartsNoScans() async {
        let scanner = ControlledScanner(apps: [], commands: [])
        let model = LauncherModel(scanner: scanner, settings: makeSettings(), snapshot: CatalogSnapshot(apps: [safari], commands: [planets]))
        #expect(scanner.startedScans.value == 0)
        #expect(model.isLoadingCatalog == false, "readiness starts complete with a snapshot")
        #expect(model.allCommands.map(\.id) == [planets.id])
        model.query = "planets"
        #expect(model.results.first?.item.id == "command:sample/planets", "a preloaded model ranks normally")
        await model.waitForCommands()
    }

    // MARK: Publication

    @Test func scansPublishTheirResultsAndCompleteLoading() async {
        let scanner = ControlledScanner(apps: [[safari]], commands: [[planets]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 2") { scanner.startedScans.value >= 2 }

        await scanner.openAppScan(at: 0)
        await waitFor("safari apps") { model.apps.map(\.name) == [safari.name] }
        #expect(model.isLoadingCatalog, "commands are still loading")

        await scanner.openCommandScan(at: 0)
        await waitFor("!model.isLoadingCatalog") { !model.isLoadingCatalog }
        #expect(model.allCommands.map(\.id) == [planets.id])
        let ids = model.results.map(\.id)
        #expect(ids.contains("app:\(safari.url.path)"))
        #expect(ids.contains("command:\(planets.id)"))
    }

    @Test func aQueryTypedDuringALoadIsUsedWhenItPublishes() async {
        let forecast = Fixture.command("forecast", extension: "weather", title: "Forecast")
        let scanner = ControlledScanner(apps: [], commands: [[planets, forecast]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 1") { scanner.startedScans.value >= 1 }
        model.query = "forecast"

        await scanner.openCommandScan(at: 0)
        // Fallback rows show while loading, so wait for the command itself.
        await waitFor("forecast published") { model.results.contains { $0.item.id == "command:weather/forecast" } }
        #expect(model.results.first?.item.id == "command:weather/forecast", "the query typed mid-load filters the published results")
        #expect(!model.results.contains { $0.item.id == "command:sample/planets" })
    }

    @Test func anOlderRequestCannotOverwriteANewerOne() async {
        let scanner = ControlledScanner(apps: [[safari]], commands: [[planets], [weather]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        await waitFor("both initial scans") { scanner.startedScans.value >= 2 }
        await scanner.openAppScan(at: 0)
        await waitFor("initial apps") { model.apps.map(\.name) == [safari.name] }

        model.reloadCommands()
        await waitFor("second command scan") { scanner.startedScans.value >= 3 }
        #expect(model.isLoadingCatalog, "the newer request keeps the load marked as running")

        await scanner.openCommandScan(at: 0)
        #expect(model.allCommands.isEmpty, "the stale result is dropped, not applied")
        #expect(model.isLoadingCatalog, "only the newest request may finish the load")

        await scanner.openCommandScan(at: 1)
        await waitFor("the newest load") { !model.isLoadingCatalog }
        #expect(model.allCommands.map(\.id) == [weather.id])
        #expect(scanner.receivedIncludeRaycast.all == [true, true], "includeRaycast is captured when the request is made")
    }

    @Test func olderAppsResultsCannotOverwriteNewerApps() async {
        let finder = appEntry("Finder")
        let scanner = ControlledScanner(apps: [[safari], [finder]], commands: [])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 1") { scanner.startedScans.value >= 1 }

        model.reloadApps()
        await waitFor("scanner.startedScans.value >= 2") { scanner.startedScans.value >= 2 }

        await scanner.openAppScan(at: 0)
        #expect(model.apps.isEmpty, "the stale app scan is dropped")

        await scanner.openAppScan(at: 1)
        await waitFor("finder apps") { model.apps.map(\.name) == [finder.name] }
    }

    @Test func aRescanKeepsThePreviousResultsVisible() async {
        let scanner = ControlledScanner(apps: [[safari]], commands: [[planets], [planets]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 2") { scanner.startedScans.value >= 2 }
        await scanner.openAppScan(at: 0)
        await scanner.openCommandScan(at: 0)
        await waitFor("!model.isLoadingCatalog") { !model.isLoadingCatalog }

        model.reloadCommands()
        await waitFor("scanner.startedScans.value >= 3") { scanner.startedScans.value >= 3 }
        #expect(model.allCommands.map(\.id) == [planets.id], "results stay while the rescan runs")

        await scanner.openCommandScan(at: 1)
        await waitFor("!model.isLoadingCatalog") { !model.isLoadingCatalog }
        #expect(model.allCommands.map(\.id) == [planets.id])
    }

    // MARK: Readiness

    @Test func anEmptyCatalogStillCompletesReadiness() async {
        let scanner = ControlledScanner(apps: [], commands: [])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 2") { scanner.startedScans.value >= 2 }
        await scanner.openAppScan(at: 0)
        await scanner.openCommandScan(at: 0)
        await model.waitForCommands()
        await waitFor("!model.isLoadingCatalog") { !model.isLoadingCatalog }
        #expect(model.allCommands.isEmpty, "empty success is still success")
    }

    @Test func readinessCallersShareOneLoadAndFollowItsReplacement() async {
        let scanner = ControlledScanner(apps: [], commands: [[planets], [weather]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        // Results are handed out in the order scans reach the scanner, so the first must be there before the second starts.
        await waitFor("the first command scan") { scanner.startedCommandScans.value >= 1 }

        let firstDone = Gate()
        let secondDone = Gate()
        Task { await model.waitForCommands(); await firstDone.open() }
        Task { await model.waitForCommands(); await secondDone.open() }

        model.reloadCommands()
        await waitFor("the second command scan") { scanner.startedCommandScans.value >= 2 }
        await scanner.openCommandScan(at: 0)
        await scanner.openCommandScan(at: 1)
        await firstDone.wait()
        await secondDone.wait()
        #expect(model.allCommands.map(\.id) == [weather.id], "a caller that returns sees the newest catalog, not a stale one")
    }

    @Test func readinessReturnsImmediatelyWhenNothingIsLoading() async {
        let scanner = ControlledScanner(apps: [], commands: [])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        await model.waitForCommands()
        #expect(scanner.startedScans.value == 0)
    }

    @Test func theMainActorStaysFreeWhileScansAreSuspended() async {
        let scanner = ControlledScanner(apps: [[safari]], commands: [[planets]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 2") { scanner.startedScans.value >= 2 }
        let sentinel = Task { @MainActor in 42 }
        #expect(await sentinel.value == 42, "the model never waits synchronously for a scan")
    }

    @Test func theModelCanBeReleasedWhileAScanIsSuspended() async {
        let scanner = ControlledScanner(apps: [[safari]], commands: [[planets]])
        weak var weakModel: LauncherModel?
        autoreleasepool {
            let model = LauncherModel(scanner: scanner, settings: makeSettings())
            weakModel = model
            model.startCatalogLoading()
        }
        // A task that is just starting may hold the model for a moment; what matters is that it lets go.
        await waitFor("the model is released") { weakModel == nil }
        #expect(weakModel == nil, "a suspended scan holds the scanner, not the model")
        await scanner.openAppScan(at: 0)
        await scanner.openCommandScan(at: 0)
    }

    // MARK: Autorun

    @Test func autorunWaitsForReadinessThenRunsAtMostOnce() async {
        let scanner = ControlledScanner(apps: [], commands: [[planets]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        let launched = Gate()
        let recorder = LaunchRecorder()
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 1") { scanner.startedScans.value >= 1 }

        // Both waits join the same load; whichever resumes first takes the one-shot, so both ask
        // for the same command and exactly one launch is observable.
        model.autorun(target: planets.id) { command in
            Task { await recorder.record(command); await launched.open() }
        }
        model.autorun(target: planets.id) { command in
            Task { await recorder.record(command); await launched.open() }
        }

        await scanner.openCommandScan(at: 0)
        await launched.wait()
        try? await Task.sleep(for: .milliseconds(20))
        let recorded = await recorder.commands
        #expect(recorded.map(\.id) == [planets.id], "readiness unblocks both waits, but only the first autorun launches")
    }

    @Test func autorunForAnAbsentCommandLaunchesNothing() async {
        let scanner = ControlledScanner(apps: [], commands: [[planets]])
        let model = LauncherModel(scanner: scanner, settings: makeSettings())
        let recorder = LaunchRecorder()
        model.startCatalogLoading()
        await waitFor("scanner.startedScans.value >= 1") { scanner.startedScans.value >= 1 }

        model.autorun(target: "missing/command") { command in
            Task { await recorder.record(command) }
        }
        await scanner.openCommandScan(at: 0)
        await model.waitForCommands()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.commands.isEmpty)
    }
}

/// Records launches away from the test, so counts are readable after the gates settle.
private actor LaunchRecorder {
    private(set) var commands: [ExtensionCommand] = []

    func record(_ command: ExtensionCommand) {
        commands.append(command)
    }
}
