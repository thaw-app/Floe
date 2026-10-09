//
//  TimersTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct TimersTests {
    /// What stands in for the clock, the notifications and the waiting: nothing is posted and no time passes.
    private final class Stand {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var isAllowed = true
        var asked = 0
        var notified: [RunningTimer] = []
        var waits: [(seconds: TimeInterval, fire: () -> Void)] = []
        var calledOff = 0
    }

    private static nonisolated let english = Locale(identifier: "en_US")

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-timers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A model whose receipts are in the folder and whose timers go to the stand-in.
    private func model(in folder: URL, stand: Stand) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-timers-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.timing = TimerEnvironment(
            now: { stand.now },
            requestAccess: {
                stand.asked += 1
                return stand.isAllowed
            },
            notify: { stand.notified.append($0) },
            wait: { seconds, fire in
                stand.waits.append((seconds, fire))
                return { stand.calledOff += 1 }
            }
        )
        return model
    }

    // MARK: The length

    @Test(arguments: [
        ("timer 10 minutes", 600.0, ""),
        ("timer 25m", 1500.0, ""),
        ("timer 1h 30m", 5400.0, ""),
        ("timer 1h30m", 5400.0, ""),
        ("timer 90s", 90.0, ""),
        ("timer 5 min tea", 300.0, "tea"),
        ("Timer  5 MIN  Tea Time", 300.0, "Tea Time"),
        ("timer 1 hour 15 minutes 30 seconds", 4530.0, ""),
        ("timer 1.5h", 5400.0, ""),
        ("timer 2 hrs for the roast", 7200.0, "the roast"),
        ("timer 45 secs", 45.0, ""),
        ("timer 10", 600.0, ""),
        ("timer 3 eggs", 180.0, "eggs"),
        ("timer 5 mango", 300.0, "mango"),
        ("timer 24h", 86400.0, ""),
        ("timer 20m 2 eggs", 1200.0, "2 eggs"),
    ])
    func theKeywordAndALength(query: String, seconds: Double, label: String) {
        #expect(TimerDraft.request(in: query) == TimerDraft(duration: seconds, label: label))
    }

    @Test(arguments: [
        "timer", "timer ", "timer tea", "timer 0", "timer 0m", "timer 0h 0s", "timer 25h", "timer 24h 1s", "timer 1441",
        "timer 5x", "timer 1:30", "timer -5m", "timers 5m", "timer five minutes", "5m timer",
    ])
    func anythingElseIsAnOrdinarySearch(query: String) {
        #expect(TimerDraft.request(in: query) == nil)
        #expect(TimerSearchProvider().contribution(for: SearchContext(query: query)).pinned.isEmpty)
    }

    @Test func aLengthIsReadAsAPersonWouldSayIt() {
        #expect(TimeLength.text(600, locale: Self.english) == "10 min")
        #expect(TimeLength.text(5400, locale: Self.english) == "1 hr, 30 min")
        #expect(TimeLength.text(90, locale: Self.english) == "1 min, 30 sec")
        #expect(TimeLength.clock(252, locale: Self.english) == "4:12")
        #expect(TimeLength.clock(251.2, locale: Self.english) == "4:12", "a started second is still on the clock")
        #expect(TimeLength.clock(3852, locale: Self.english) == "1:04:12")
        #expect(TimeLength.clock(-3, locale: Self.english) == "0:00")
    }

    // MARK: The rows

    @Test func theRowSaysHowLongAndShowsTheLabel() {
        let plain = RootItem.timer(.draft(TimerDraft(duration: 600)))
        #expect(plain.title == "Timer: \(TimeLength.text(600))")
        #expect(plain.rowLabel == "Timer")
        #expect(plain.kind == "Timer")
        #expect(plain.id == "timer-draft")
        #expect(plain.isScopeResult)
        #expect(plain.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(plain), "a length being typed is not something to favorite")
        #expect(RootItem.timer(.draft(TimerDraft(duration: 300, label: "tea"))).rowLabel == "tea")

        let pinned = TimerSearchProvider().contribution(for: SearchContext(query: "timer 5 min tea")).pinned
        #expect(pinned.map(\.item.title) == ["Timer: \(TimeLength.text(300))"])
        #expect(pinned.map(\.item.rowLabel) == ["tea"])
    }

    @Test func aRunningTimerShowsItsNameAndTheTimeLeft() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tea = RunningTimer(label: "tea", duration: 300, ends: now.addingTimeInterval(252))
        #expect(tea.name == "tea")
        #expect(tea.left(now: now, locale: Self.english) == "4:12 left")
        #expect(tea.left(now: now.addingTimeInterval(900), locale: Self.english) == "0:00 left")
        let plain = RunningTimer(duration: 600, ends: now.addingTimeInterval(600))
        #expect(plain.name == TimeLength.text(600))

        let row = RootItem.timer(.running(tea))
        #expect(row.title == "tea")
        #expect(row.id == "timer:\(tea.id.uuidString)")
        #expect(row.rowLabel.hasSuffix(" left"))
        #expect(row.isScopeResult)
        #expect(!LauncherModel.keepsItsPlace(row))
    }

    // MARK: The list

    @Test func timersListsTheOnesRunningTheFirstToEndOnTop() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tea = RunningTimer(label: "tea", duration: 300, ends: now.addingTimeInterval(300))
        let roast = RunningTimer(label: "roast", duration: 7200, ends: now.addingTimeInterval(7200))
        let eggs = RunningTimer(label: "eggs", duration: 180, ends: now.addingTimeInterval(180))
        let scope = TimersSearchScope()
        let context: (String) -> SearchContext = { query in
            var context = SearchContext(query: query)
            context.timers = [tea, roast, eggs]
            return context
        }
        #expect(scope.text(in: context("timers")) == "")
        #expect(scope.text(in: context("Timers ")) == "")
        #expect(scope.text(in: context("timers tea")) == "tea")
        #expect(scope.text(in: context("timer 5m")) == nil)
        #expect(scope.text(in: context("timersx")) == nil)
        #expect(scope.results(for: "", context: context("timers")).map(\.title) == ["eggs", "tea", "roast"])
        #expect(scope.results(for: "EA", context: context("timers EA")).map(\.title) == ["tea"])
        #expect(scope.results(for: "soup", context: context("timers soup")).map(\.title) == [])
        #expect(scope.results(for: "", context: SearchContext(query: "timers")).map(\.title) == [])

        let match = try #require(RootSearch.scope(in: context("timers"), scopes: RootSearch.standardScopes()))
        #expect(match.scope.keyword == "timers")
        #expect(RootSearch.scope(in: context("timer 5m"), scopes: RootSearch.standardScopes()) == nil)
    }

    // MARK: Return

    @Test func returnStartsTheTimerSaysSoAndLeavesAReceipt() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "timer 5 min tea"
        let row = try #require(model.results.first?.item)
        #expect(row.title == "Timer: \(TimeLength.text(300))")
        #expect(row.rowLabel == "tea")
        #expect(model.primaryActionTitle(for: row) == "Start Timer")
        #expect(model.rootActions(for: row).compactMap { $0?.title } == ["Start Timer"])
        guard case let .timer(.draft(draft)) = row else {
            Issue.record("the row is not the one that starts a timer")
            return
        }

        model.activate(row)
        #expect(hidden == 1)
        #expect(model.query.isEmpty)
        #expect(said == ["Timer started: tea"])
        #expect(stand.waits.map(\.seconds) == [300])
        let running = try #require(model.runningTimers.all.first)
        #expect(running.label == "tea")
        #expect(running.duration == 300)
        #expect(running.ends == stand.now.addingTimeInterval(300))
        #expect(stand.notified.isEmpty)

        await model.startTimer(draft).value
        #expect(stand.asked == 2, "each start asks whether Floe may post, and macOS shows its question once")
        #expect(model.runningTimers.all.count == 2)

        let receipt = try #require(model.receipts.all.last)
        #expect(receipt.kind == .timer)
        #expect(receipt.subject == "tea")
        #expect(receipt.detail == TimeLength.text(300))
        #expect(receipt.identifier == running.id.uuidString)
        #expect(receipt.date == stand.now)
        #expect(receipt.title == "Started the timer tea")
    }

    @Test func aTimerWithNoLabelIsCalledByItsLength() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.startTimer(TimerDraft(duration: 600)).value
        #expect(said == ["Timer started: \(TimeLength.text(600))"])
        #expect(model.receipts.all.first?.subject == TimeLength.text(600))

        model.settings.keepsReceipts = false
        await model.startTimer(TimerDraft(duration: 60)).value
        #expect(model.runningTimers.all.count == 2)
        #expect(model.receipts.all.count == 1, "receipts switched off: the timer runs and no record is kept")
    }

    // MARK: The end

    @Test func whenItEndsANotificationSaysSoAndTheTimerIsOffTheList() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.startTimer(TimerDraft(duration: 300, label: "tea")).value
        await model.startTimer(TimerDraft(duration: 600)).value
        said.removeAll()

        stand.waits[0].fire()
        #expect(model.runningTimers.all.map(\.duration) == [600])
        await model.runningTimers.announcement?.value
        #expect(stand.notified.map(\.name) == ["tea"])
        #expect(said.isEmpty, "the notification says it, so the HUD does not")
        #expect(stand.calledOff == 1)

        stand.waits[0].fire()
        await model.runningTimers.announcement?.value
        #expect(stand.notified.count == 1, "a timer ends once")
    }

    @Test func withNotificationsRefusedTheHUDSaysItEnded() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.isAllowed = false
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.startTimer(TimerDraft(duration: 300, label: "tea")).value
        #expect(said == ["Timer started: tea"])

        stand.waits[0].fire()
        await model.runningTimers.announcement?.value
        #expect(stand.notified.isEmpty)
        #expect(said.last == "Timer ended: tea")
        #expect(model.runningTimers.all.isEmpty)
    }

    // MARK: Stopping

    @Test func returnOnARunningTimerStopsIt() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.startTimer(TimerDraft(duration: 300, label: "tea")).value
        await model.startTimer(TimerDraft(duration: 120, label: "eggs")).value

        model.query = "timers"
        #expect(model.results.map(\.item.title) == ["eggs", "tea"])
        #expect(model.results.compactMap(\.section) == ["Timers", "Timers"])
        let row = try #require(model.results.first?.item)
        #expect(model.primaryActionTitle(for: row) == "Stop Timer")

        model.activate(row)
        #expect(said.last == "Stopped the timer eggs")
        #expect(model.runningTimers.all.map(\.label) == ["tea"])
        #expect(stand.calledOff == 1)

        model.activate(row)
        #expect(said.last == "The timer eggs is no longer running")
        #expect(stand.calledOff == 1)
        #expect(stand.notified.isEmpty)
    }

    @Test func returnOnTheReceiptStopsTheTimerWhileItRuns() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.startTimer(TimerDraft(duration: 300, label: "tea")).value
        let receipt = try #require(model.receipts.all.first)
        let row = RootItem.receipt(receipt)
        #expect(receipt.canUndo)
        #expect(receipt.label().hasSuffix(" · can be stopped"))
        #expect(model.primaryActionTitle(for: row) == "Stop Timer")
        #expect(model.rootActions(for: row).map { $0?.title ?? "-" } == ["Stop Timer", "Show Details", "-", "Copy"])

        model.activate(row)
        #expect(said.last == "Stopped the timer tea")
        #expect(model.runningTimers.all.isEmpty)
        #expect(stand.calledOff == 1)
        let after = try #require(model.receipts.all.first)
        #expect(!after.canUndo, "once is enough")
        #expect(after.label().hasSuffix(" · stopped"))
        #expect(after.text.contains("\nStopped "))
        #expect(model.primaryActionTitle(for: .receipt(after)) == "Show Details")
    }

    @Test func theReceiptOfATimerThatEndedSaysItIsNoLongerRunning() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.startTimer(TimerDraft(duration: 300, label: "tea")).value
        stand.waits[0].fire()
        await model.runningTimers.announcement?.value

        try model.undo(#require(model.receipts.all.first))
        #expect(said.last == "The timer tea is no longer running")
        #expect(model.receipts.all.first?.canUndo == false)
        #expect(!model.stopTimer("not an identifier"))
    }
}
