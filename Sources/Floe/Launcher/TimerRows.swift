//
//  TimerRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What a timer reaches outside the launcher through. Tests replace all of it, so none posts a notification or waits.
struct TimerEnvironment {
    var now: () -> Date = { Date() }
    /// Whether Floe may post notifications. macOS asks the user the first time.
    var requestAccess: () async -> Bool = { await TimerAlerts.requestAccess() }
    /// Posts the notification that says a timer ended.
    var notify: (RunningTimer) -> Void = { TimerAlerts.post($0) }
    /// Calls back after that many seconds. What it answers calls the wait off.
    var wait: (TimeInterval, @escaping () -> Void) -> () -> Void = { TimerAlerts.wait($0, then: $1) }
}

/// The timers that are counting down, each with what calls its wait off.
final class RunningTimers {
    private(set) var all: [RunningTimer] = []
    private var waits: [UUID: () -> Void] = [:]
    var onChange: (() -> Void)?

    /// Replaces the foreground snapshot without scheduling countdowns or echoing an onChange event.
    func mirror(_ timers: [RunningTimer]) {
        all = timers
    }

    /// The telling of the last timer that ended, for a test to wait on.
    var announcement: Task<Void, Never>?

    /// Registers a resident countdown and its cancellation callback before notifying mirrors.
    func add(_ timer: RunningTimer, stop: @escaping () -> Void) {
        all.append(timer)
        waits[timer.id] = stop
        onChange?()
    }

    /// Takes a timer off the list. Nil when it is not on it: it ended, or was stopped.
    func remove(_ id: UUID) -> RunningTimer? {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        waits.removeValue(forKey: id)?()
        let removed = all.remove(at: index)
        onChange?()
        return removed
    }
}

/// Timers, as the launcher starts, ends and stops them. The resident runs the countdowns; the panel process
/// keeps a copy of the list and sends what it is asked to the resident.
final class TimerRows {
    var environment = TimerEnvironment()
    var host = RowHost()
    /// Sends a request to the resident, in the panel process. Nil in the resident.
    var toResident: () -> ((PanelPacket) -> Void)? = { nil }
    let running = RunningTimers()

    /// Starts the countdown and leaves a receipt that can stop it. The task is for a test to wait on.
    @discardableResult
    func startTimer(_ draft: TimerDraft) -> Task<Void, Never> {
        host.leave()
        if let residentRequests = toResident() {
            residentRequests(.startTimer(draft))
            return Task {
                // The resident owns the countdown; this task acknowledges only the forwarded request.
            }
        }
        let timer = RunningTimer(label: draft.label, duration: draft.duration, ends: environment.now().addingTimeInterval(draft.duration))
        let stop = environment.wait(draft.duration) { [weak self] in self?.timerEnded(timer.id) }
        running.add(timer, stop: stop)
        host.record(Receipt(date: environment.now(), kind: .timer, subject: timer.name, detail: TimeLength.text(timer.duration), identifier: timer.id.uuidString))
        host.showHUD(String(localized: "Timer started: \(timer.name)", bundle: .floe, comment: "The placeholder is a timer's label, or how long it runs, such as 10 min."))
        // Asked now, so the question is answered long before the timer ends.
        return Task { [environment] in _ = await environment.requestAccess() }
    }

    /// The countdown ran out: a notification says so, or the HUD when Floe may not post one.
    func timerEnded(_ id: UUID) {
        guard let timer = running.remove(id) else { return }
        running.announcement = Task { [weak self, environment] in
            if await environment.requestAccess() {
                environment.notify(timer)
            } else {
                self?.host.showHUD(String(localized: "Timer ended: \(timer.name)", bundle: .floe, comment: "The placeholder is a timer's label, or how long it ran, such as 10 min."))
            }
        }
    }

    /// Return on a running timer stops it.
    func stop(_ timer: RunningTimer) {
        host.leave()
        let outcome: ReceiptUndo.Outcome = stopTimer(timer.id.uuidString) ? .deleted : .alreadyDeleted
        host.showHUD(ReceiptUndo.message(for: outcome, subject: timer.name, kind: .timer))
    }

    /// Stops the timer a receipt names, forwarding even when the local snapshot is missing it.
    /// The result describes local removal, not an acknowledgement from the resident.
    func stopTimer(_ identifier: String) -> Bool {
        guard let id = UUID(uuidString: identifier) else { return false }
        let removed = running.remove(id) != nil
        toResident()?(.stopTimer(id))
        return removed
    }
}

extension TimerRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        switch item {
        case .timer(.draft): String(localized: "Start Timer", bundle: .floe)
        case .timer(.running): String(localized: "Stop Timer", bundle: .floe)
        default: nil
        }
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case let .timer(.draft(draft)): startTimer(draft)
        case let .timer(.running(timer)): stop(timer)
        default: return false
        }
        return true
    }
}
