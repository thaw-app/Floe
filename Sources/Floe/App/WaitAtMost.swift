//
//  WaitAtMost.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

/// Runs `work` and calls `done` once: when the work ends, or when `limit` has passed, whichever comes first.
/// What Floe saves before it quits goes through it, since AppKit greys out Quit until the quit is answered.
func waitAtMost(_ limit: Duration, for work: @escaping () async -> Void, then done: @escaping () -> Void) {
    let once = CallOnce<Void> { done() }
    Task {
        await work()
        once.call(())
    }
    Task {
        try? await Task.sleep(for: limit)
        once.call(())
    }
}

/// What `work` gives, or `fallback` once `limit` has passed. The work is not stopped, since a read of a volume
/// that stopped answering can't be: its answer is only let go.
func waitAtMost<Value: Sendable>(_ limit: Duration, otherwise fallback: Value, for work: @escaping () async -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        let once = CallOnce<Value> { continuation.resume(returning: $0) }
        Task {
            // The limit runs from when the work starts: a busy executor that holds the work back holds it back too.
            let timer = Task {
                try? await Task.sleep(for: limit)
                once.call(fallback)
            }
            await once.call(work())
            timer.cancel()
        }
    }
}

private final class CallOnce<Value> {
    private var action: ((Value) -> Void)?

    init(_ action: @escaping (Value) -> Void) {
        self.action = action
    }

    func call(_ value: Value) {
        let action = action
        self.action = nil
        action?(value)
    }
}
