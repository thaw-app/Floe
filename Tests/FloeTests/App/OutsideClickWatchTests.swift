//
//  OutsideClickWatchTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

/// Stands in for AppKit's event monitors: keeps each handler and records what was removed.
@MainActor
final class MonitorStub {
    var handlers: [Int: () -> Void] = [:]
    var removed: [Int] = []
    private var next = 0

    func watch() -> OutsideClickWatch {
        OutsideClickWatch(
            install: { [unowned self] onClick in
                next += 1
                handlers[next] = onClick
                return next
            },
            remove: { [unowned self] in removed.append($0 as? Int ?? -1) }
        )
    }

    func click() {
        handlers.filter { !removed.contains($0.key) }.values.forEach { $0() }
    }
}

@MainActor struct OutsideClickWatchTests {
    private let monitors = MonitorStub()

    @Test func aClickInAnotherAppIsReportedUntilTheWatchStops() {
        let watch = monitors.watch()
        var clicks = 0
        watch.start { clicks += 1 }
        #expect(watch.isWatching)
        monitors.click()
        #expect(clicks == 1)
        watch.stop()
        #expect(!watch.isWatching)
        #expect(monitors.removed == [1])
        monitors.click()
        #expect(clicks == 1)
        watch.stop()
        #expect(monitors.removed == [1], "stopping twice removes nothing more")
    }

    @Test func startingAgainReplacesTheEarlierWatch() {
        let watch = monitors.watch()
        watch.start {}
        watch.start {}
        #expect(monitors.removed == [1], "one watch at a time, so a click closes the launcher once")
        #expect(watch.isWatching)
    }

    @Test func aMonitorAppKitRefusesLeavesNothingToStop() {
        let watch = OutsideClickWatch(install: { _ in nil }, remove: { _ in Issue.record("nothing was installed") })
        watch.start {}
        #expect(!watch.isWatching)
        watch.stop()
    }

    @Test func theRealMonitorInstallsAndGoes() {
        let watch = OutsideClickWatch()
        watch.start {}
        #expect(watch.isWatching)
        watch.stop()
        #expect(!watch.isWatching)
    }
}
