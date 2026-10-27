//
//  WaitAtMost.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

/// Runs `work` and calls `done` once: when the work ends, or when `limit` has passed, whichever comes first.
/// What Floe saves before it quits goes through it, since AppKit greys out Quit until the quit is answered.
func waitAtMost(_ limit: Duration, for work: @escaping () async -> Void, then done: @escaping () -> Void) {
    let once = CallOnce(done)
    Task {
        await work()
        once.call()
    }
    Task {
        try? await Task.sleep(for: limit)
        once.call()
    }
}

private final class CallOnce {
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func call() {
        let action = action
        self.action = nil
        action?()
    }
}
