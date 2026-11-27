//
//  LauncherWindowTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor struct LauncherWindowTests {
    private func launcher(idleTrimDelay: Duration = .seconds(300), outsideClicks: OutsideClickWatch = OutsideClickWatch()) -> (LauncherWindow, LauncherModel) {
        let settings = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        _ = NSApplication.shared
        let window = LauncherWindow(
            model: model, settings: settings, idleTrimDelay: idleTrimDelay, outsideClicks: outsideClicks,
            present: { panel in
                panel.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                panel.orderFrontRegardless()
            }
        ) { _ in }
        return (window, model)
    }

    @Test func aClickInAnotherAppClosesTheLauncher() {
        let monitors = MonitorStub()
        let watch = monitors.watch()
        let (launcher, _) = launcher(outsideClicks: watch)
        launcher.show()
        #expect(launcher.isVisible)
        #expect(watch.isWatching, "showing the launcher watches other apps' clicks")
        monitors.click()
        #expect(!launcher.isVisible)
        #expect(!watch.isWatching, "a closed launcher watches nothing")
    }

    @Test func aClickWhileAChooserIsOpenLeavesTheLauncherOpen() {
        let monitors = MonitorStub()
        let watch = monitors.watch()
        let (launcher, _) = launcher(outsideClicks: watch)
        launcher.show()
        ModalGuard.run { monitors.click() }
        #expect(launcher.isVisible, "a click in a file or app chooser is not a click away from the launcher")
        #expect(watch.isWatching)
        launcher.hide()
        #expect(!watch.isWatching)
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

    @Test func aTrimThatHadToWaitIsTriedAgain() async throws {
        let (launcher, model) = launcher(idleTrimDelay: .milliseconds(50))
        model.query = "half typed"
        model.setup = SetupRequest(command: Fixture.command("planets"), kind: .arguments, fields: [])
        launcher.trim()
        #expect(model.query == "half typed")
        model.setup = nil
        for _ in 0 ..< 100 where !model.query.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.query.isEmpty, "once the form is gone, the next try lets go")
    }
}
