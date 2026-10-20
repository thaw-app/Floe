//
//  LauncherWindowTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

@MainActor struct LauncherWindowTests {
    private func launcher(idleTrimDelay: Duration = .seconds(300)) -> (LauncherWindow, LauncherModel) {
        let settings = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        return (LauncherWindow(model: model, settings: settings, idleTrimDelay: idleTrimDelay) { _ in }, model)
    }

    @Test func aLauncherLeftClosedTrimsItselfOnceTheDelayHasPassed() async throws {
        let (launcher, model) = launcher(idleTrimDelay: .milliseconds(50))
        model.query = "half typed"
        launcher.scheduleIdleTrim()
        #expect(model.query == "half typed", "nothing goes before the delay")
        for _ in 0 ..< 100 where !model.query.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.query.isEmpty)
    }

    @Test func aTrimWhileClosedLetsGoOfTheSearchToo() {
        let (launcher, model) = launcher()
        model.query = "half typed"
        #expect(!launcher.isVisible)
        launcher.trim()
        #expect(model.query.isEmpty, "the next show starts from the root search, as a new window would")
    }

    @Test func aTrimLeavesACommandThatIsAskingForItsSetupAlone() {
        let (launcher, model) = launcher()
        model.query = "half typed"
        model.setup = SetupRequest(command: Fixture.command("planets"), kind: .arguments, fields: [])
        launcher.trim()
        #expect(model.query == "half typed", "a form being filled in is not taken away")
        #expect(model.setup != nil)
    }
}
