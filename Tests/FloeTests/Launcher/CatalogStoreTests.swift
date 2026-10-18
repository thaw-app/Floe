//
//  CatalogStoreTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Answers each scan at once with what it was given, and remembers what it was asked.
private actor FixedScanner: CatalogScanning {
    private let apps: [AppEntry]
    private var commands: [[ExtensionCommand]]
    private(set) var includeRaycast: [Bool] = []

    init(apps: [AppEntry], commands: [[ExtensionCommand]]) {
        self.apps = apps
        self.commands = commands
    }

    func scanApps() async -> [AppEntry] {
        apps
    }

    func scanCommands(includeRaycast: Bool) async -> [ExtensionCommand] {
        self.includeRaycast.append(includeRaycast)
        return commands.count > 1 ? commands.removeFirst() : commands.first ?? []
    }
}

@MainActor
struct CatalogStoreTests {
    private let planets = Fixture.command("planets", extension: "sample", title: "Planets")
    private let forecast = Fixture.command("forecast", extension: "weather", title: "Forecast")
    private let safari = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))

    /// A scan publishes on the main actor a few hops later; this polls for it with a limit.
    private func waitFor(_ label: String, _ condition: () async -> Bool) async {
        for _ in 0 ..< 1000 {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func makeSettings() throws -> (ScratchDefaults, AppSettings) {
        let scratch = ScratchDefaults()
        return (scratch, AppSettings(defaults: scratch.defaults, savesAfterEdits: false))
    }

    @Test func aSnapshotFillsTheCatalogWithoutAScan() throws {
        let (scratch, settings) = try makeSettings()
        let catalog = CatalogStore(
            scanner: FixedScanner(apps: [], commands: []),
            settings: settings,
            snapshot: CatalogSnapshot(apps: [safari], commands: [planets])
        )
        #expect(catalog.allCommands.map(\.id) == [planets.id])
        #expect(catalog.apps.map(\.name) == ["Safari"])
        withExtendedLifetime(scratch) {}
    }

    @Test func theSettingsProcessScansItsOwnCatalog() async throws {
        let (scratch, settings) = try makeSettings()
        let catalog = CatalogStore(scanner: FixedScanner(apps: [safari], commands: [[planets]]), settings: settings)
        #expect(catalog.allCommands.isEmpty, "construction scans nothing")
        catalog.reloadAll()
        await waitFor("commands") { catalog.allCommands.map(\.id) == [planets.id] }
        await waitFor("apps") { catalog.apps.map(\.name) == ["Safari"] }
        #expect(catalog.allScripts.isEmpty)
        withExtendedLifetime(scratch) {}
    }

    @Test func aRescanReplacesTheCommandsAndReadsTheRaycastSwitch() async throws {
        let (scratch, settings) = try makeSettings()
        let scanner = FixedScanner(apps: [], commands: [[planets], [planets, forecast]])
        let catalog = CatalogStore(scanner: scanner, settings: settings)
        catalog.reloadCommands()
        await waitFor("first scan") { catalog.allCommands.map(\.id) == [planets.id] }
        settings.includeRaycastExtensions = false
        catalog.reloadCommands()
        await waitFor("second scan") { catalog.allCommands.map(\.id) == [planets.id, forecast.id] }
        #expect(await scanner.includeRaycast == [true, false])
        withExtendedLifetime(scratch) {}
    }

    @Test func itIsLoadingUntilAppsCommandsAndScriptsAreEachScannedAndSaysWhichPartChanged() async throws {
        let (scratch, settings) = try makeSettings()
        let catalog = CatalogStore(scanner: FixedScanner(apps: [safari], commands: [[planets]]), settings: settings)
        var changed: [CatalogStore.Part] = []
        catalog.onChange = { changed.append($0) }
        #expect(catalog.isLoading)
        catalog.reloadAll()
        await waitFor("all three parts") { !catalog.isLoading }
        #expect(Set(changed.map { "\($0)" }) == ["apps", "commands", "scripts"], "each part's first scan is a change")

        changed = []
        catalog.reloadScripts()
        #expect(catalog.isLoading, "a rescan is loading until it answers")
        await waitFor("the rescan") { !catalog.isLoading }
        #expect(changed.isEmpty, "the same scripts again change nothing")

        catalog.reloadScripts(quietly: true)
        #expect(!catalog.isLoading, "the rescan on each panel open shows no spinner")
        withExtendedLifetime(scratch) {}
    }
}
