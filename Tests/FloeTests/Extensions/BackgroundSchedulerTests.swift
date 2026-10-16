//
//  BackgroundSchedulerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor private final class StubStatusItem: MenuBarStatusItem {
    let button = FakeStatusButton()
    var menu: NSMenu?
    var statusButton: (any MenuBarStatusButton)? {
        button
    }
}

/// Stands in for the extension hosts: a started session is only remembered.
@MainActor private final class StartedSessions {
    var sessions: [ExtensionSession] = []

    var host: MenuBarHost {
        var host = MenuBarHost()
        host.addItem = { StubStatusItem() }
        host.removeItem = { _ in /* nothing reached the menu bar */ }
        host.start = { [unowned self] in sessions.append($0) }
        host.resolver = { _ in MenuBarFixture.resolver }
        host.icons = IconThumbnailCache { _ in MenuBarFixture.bitmap() }
        return host
    }
}

/// Intervals are an hour or more, so no timer fires while a test runs; a tick is `fire` called by hand.
@MainActor
final class BackgroundSchedulerTests {
    private static let extensionName = "floe-background-scheduler"

    private let started = StartedSessions()
    private let status = BackgroundSchedulerTests.command("status", mode: "menu-bar", title: "Status")
    private let settings: AppSettings
    private let model: LauncherModel
    private let menuBar: MenuBarCommands
    private let scheduler: BackgroundScheduler

    init() throws {
        settings = AppSettings(defaults: MemoryDefaults())
        settings.menuBarCommands = [status.id]
        let current = Self.command("status", mode: "menu-bar", title: "Current")
        model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [current]))
        menuBar = MenuBarCommands(model: model, host: started.host)
        scheduler = BackgroundScheduler(model: model, menuBarCommands: menuBar)
    }

    isolated deinit {
        scheduler.stopAll()
    }

    private static func command(
        _ name: String,
        mode: String = "no-view",
        interval: TimeInterval? = 3600,
        title: String = "Command",
        arguments: [FieldSpec] = []
    ) -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/\(extensionName)"),
            extensionName: extensionName,
            extensionTitle: "Tests",
            source: .local,
            name: name,
            title: title,
            mode: mode,
            interval: interval,
            icon: nil,
            arguments: arguments,
            extensionPreferences: [],
            commandPreferences: []
        )
    }

    @Test func onlyACommandWithAnIntervalGetsATimer() throws {
        let hourly = Self.command("hourly")
        scheduler.sync([hourly, Self.command("once", interval: nil), status])
        #expect(Set(scheduler.timers.keys) == [hourly.id, status.id])

        let timer = try #require(scheduler.timers[hourly.id])
        #expect(timer.isValid)
        #expect(timer.timeInterval == 3600)
        #expect(timer.tolerance == 360)
    }

    @Test func aCommandThatNeedsAnArgumentIsNeverScheduled() {
        let asks = Self.command("asks", arguments: [Fixture.field("query", required: true)])
        let offers = Self.command("offers", arguments: [Fixture.field("query")])
        scheduler.sync([asks, offers])
        #expect(Array(scheduler.timers.keys) == [offers.id])
    }

    @Test func aCommandOffByDefaultIsScheduledOnlyOnceItIsSwitchedOn() {
        var renew = Self.command("renew")
        renew.isDisabledByDefault = true
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [renew]))
        scheduler.sync(model.enabledCommands)
        #expect(scheduler.timers.isEmpty)

        settings.setEnabled(true, for: renew)
        scheduler.sync(model.enabledCommands)
        #expect(Array(scheduler.timers.keys) == [renew.id])
    }

    @Test func aCommandGoneFromTheListLosesItsTimer() throws {
        let hourly = Self.command("hourly")
        let daily = Self.command("daily", interval: 86400)
        scheduler.sync([hourly, daily])
        let stopped = try #require(scheduler.timers[hourly.id])
        let kept = try #require(scheduler.timers[daily.id])

        scheduler.sync([daily])
        #expect(Array(scheduler.timers.keys) == [daily.id])
        #expect(!stopped.isValid)
        #expect(scheduler.timers[daily.id] === kept)
        #expect(kept.isValid)
    }

    @Test func aCommandThatLosesItsIntervalLosesItsTimer() throws {
        scheduler.sync([Self.command("hourly")])
        let stopped = try #require(scheduler.timers.values.first)

        scheduler.sync([Self.command("hourly", interval: nil)])
        #expect(scheduler.timers.isEmpty)
        #expect(!stopped.isValid)
    }

    @Test func aChangedIntervalStartsANewTimer() throws {
        let hourly = Self.command("hourly")
        scheduler.sync([hourly])
        let old = try #require(scheduler.timers[hourly.id])

        scheduler.sync([Self.command("hourly", interval: 7200)])
        let new = try #require(scheduler.timers[hourly.id])
        #expect(new !== old)
        #expect(!old.isValid)
        #expect(new.isValid)
        #expect(new.timeInterval == 7200)
        #expect(scheduler.timers.count == 1)
    }

    @Test func theSameListAgainKeepsEveryTimer() {
        let commands = [Self.command("hourly"), Self.command("daily", interval: 86400)]
        scheduler.sync(commands)
        let before = scheduler.timers

        scheduler.sync(commands)
        #expect(scheduler.timers.count == 2)
        for (id, timer) in before {
            #expect(scheduler.timers[id] === timer)
            #expect(timer.isValid)
        }
    }

    @Test func stoppingEverythingInvalidatesEveryTimer() {
        scheduler.sync([Self.command("hourly"), Self.command("daily", interval: 86400)])
        let timers = Array(scheduler.timers.values)
        #expect(timers.count == 2)

        scheduler.stopAll()
        #expect(scheduler.timers.isEmpty)
        #expect(timers.allSatisfy { !$0.isValid })
    }

    @Test func aTickRestartsAMenuBarCommandAsTheCatalogNowHasIt() throws {
        menuBar.sync([status])
        let first = try #require(menuBar.session(for: status.id))
        #expect(menuBar.presenter(for: status.id)?.commandTitle == "Status")

        scheduler.fire(status)
        #expect(started.sessions.count == 2)
        #expect(first.isStopping)
        #expect(menuBar.session(for: status.id) !== first)
        #expect(menuBar.presenter(for: status.id)?.commandTitle == "Current")
    }

    @Test func aTickLeavesACommandThatNowNeedsAnArgumentAlone() throws {
        let asks = Self.command("asks", mode: "menu-bar", arguments: [Fixture.field("query", required: true)])
        menuBar.sync([asks])
        let session = try #require(menuBar.session(for: asks.id))

        scheduler.fire(asks)
        #expect(started.sessions.count == 1)
        #expect(menuBar.session(for: asks.id) === session)
        #expect(!session.isStopping)
    }
}
