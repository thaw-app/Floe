//
//  ClipboardWatcher.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Reads the pasteboard when it changes. macOS announces no change, so the change count is compared on a timer:
/// often while the keyboard or mouse is in use, seldom while they rest, never while the screens sleep.
final class ClipboardWatcher {
    struct Pace {
        var active: TimeInterval = 0.25
        var resting: TimeInterval = 1
        /// How long after the last key or click the pace stays the active one.
        var activeFor: TimeInterval = 5
        /// How many times a pasteboard that reads empty after a change is read again.
        var emptyReads = 4
    }

    private let pace: Pace
    private let changeCount: () -> Int
    private let read: () -> ClipboardCapture.Reading
    private let isRecording: () -> Bool
    private let secondsSinceInput: () -> TimeInterval
    private let deliver: (ClipboardCapture.Reading) -> Void
    private var seen: Int
    /// The reads left for the change that was seen, and zero once it is read.
    private var readsLeft = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(
        pace: Pace = Pace(),
        changeCount: @escaping () -> Int,
        read: @escaping () -> ClipboardCapture.Reading,
        isRecording: @escaping () -> Bool,
        secondsSinceInput: @escaping () -> TimeInterval = { ClipboardWatcher.secondsSinceInput() },
        deliver: @escaping (ClipboardCapture.Reading) -> Void
    ) {
        self.pace = pace
        self.changeCount = changeCount
        self.read = read
        self.isRecording = isRecording
        self.secondsSinceInput = secondsSinceInput
        self.deliver = deliver
        seen = changeCount()
    }

    /// Any key, click or movement in the login session. Needs no permission: it tells when, not what.
    static func secondsSinceInput() -> TimeInterval {
        // The event type that stands for all of them, kCGAnyInputEventType, which Swift does not bring over.
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addMainObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil) { [weak self] in self?.pause() },
            center.addMainObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil) { [weak self] in self?.schedule(after: 0) },
        ]
        schedule(after: pace.active)
    }

    func stop() {
        pause()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer.scheduledOnMain(withTimeInterval: interval, repeats: false) { [weak self] in
            guard let self else { return }
            schedule(after: tick())
        }
        // Lets the system fire this with its other timers.
        timer.tolerance = interval / 5
        self.timer = timer
    }

    /// Takes the pasteboard as it is now as seen, and drops the reads left for an earlier change. Called when
    /// recording comes back on, so a copy made while it was off and not looked at yet is never read.
    func skipToNow() {
        seen = changeCount()
        readsLeft = 0
    }

    /// Looks once, and answers how long to wait before the next look.
    func tick() -> TimeInterval {
        let count = changeCount()
        if count != seen {
            seen = count
            readsLeft = pace.emptyReads
        }
        if readsLeft > 0 {
            readNow(at: count)
        }
        return readsLeft > 0 || secondsSinceInput() < pace.activeFor ? pace.active : pace.resting
    }

    private func readNow(at count: Int) {
        // What is copied while the history is off is never read, not even once it is on again.
        guard isRecording() else {
            readsLeft = 0
            return
        }
        let reading = read()
        // Changed again while it was read: what was read may be half of each, and the next look reads the new one.
        guard changeCount() == count else { return }
        if case .empty = reading {
            readsLeft -= 1
        } else {
            readsLeft = 0
            deliver(reading)
        }
    }
}
