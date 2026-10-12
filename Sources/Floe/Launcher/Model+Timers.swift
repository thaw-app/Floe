//
//  Model+Timers.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

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

/// Timers, as the launcher starts, ends and stops them.
extension LauncherModel {
    /// Starts the countdown and leaves a receipt that can stop it. The task is for a test to wait on.
    @discardableResult
    func startTimer(_ draft: TimerDraft) -> Task<Void, Never> {
        hidePanel()
        reset()
        if let residentRequests {
            residentRequests(.startTimer(draft))
            return Task {
                // The resident owns the countdown; this task acknowledges only the forwarded request.
            }
        }
        let timer = RunningTimer(label: draft.label, duration: draft.duration, ends: timing.now().addingTimeInterval(draft.duration))
        let stop = timing.wait(draft.duration) { [weak self] in self?.timerEnded(timer.id) }
        runningTimers.add(timer, stop: stop)
        record(Receipt(date: timing.now(), kind: .timer, subject: timer.name, detail: TimeLength.text(timer.duration), identifier: timer.id.uuidString))
        showHUD(String(localized: "Timer started: \(timer.name)", bundle: .floe, comment: "The placeholder is a timer's label, or how long it runs, such as 10 min."))
        // Asked now, so the question is answered long before the timer ends.
        return Task { [timing] in _ = await timing.requestAccess() }
    }

    /// The countdown ran out: a notification says so, or the HUD when Floe may not post one.
    func timerEnded(_ id: UUID) {
        guard let timer = runningTimers.remove(id) else { return }
        runningTimers.announcement = Task { [weak self, timing] in
            if await timing.requestAccess() {
                timing.notify(timer)
            } else {
                self?.showHUD(String(localized: "Timer ended: \(timer.name)", bundle: .floe, comment: "The placeholder is a timer's label, or how long it ran, such as 10 min."))
            }
        }
    }

    /// Return on a running timer stops it.
    func stop(_ timer: RunningTimer) {
        hidePanel()
        reset()
        let outcome: ReceiptUndo.Outcome = stopTimer(timer.id.uuidString) ? .deleted : .alreadyDeleted
        showHUD(ReceiptUndo.message(for: outcome, subject: timer.name, kind: .timer))
    }

    /// Stops the timer a receipt names, forwarding even when the local snapshot is missing it.
    /// The result describes local removal, not an acknowledgement from the resident.
    func stopTimer(_ identifier: String) -> Bool {
        guard let id = UUID(uuidString: identifier) else { return false }
        let removed = runningTimers.remove(id) != nil
        residentRequests?(.stopTimer(id))
        return removed
    }
}
