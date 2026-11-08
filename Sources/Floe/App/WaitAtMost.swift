//
//  WaitAtMost.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Synchronization

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
/// that stopped answering can't be: its answer is only let go. Both run off the caller's actor, the work first in
/// line, so a pool with its hands full gets to the work before the limit, and an actor that is held delays neither.
func waitAtMost<Value: Sendable>(_ limit: Duration, otherwise fallback: Value, for work: @escaping @Sendable () async -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        let answer = Answer(continuation)
        Task { @concurrent in
            let timer = Task { @concurrent in
                try? await Task.sleep(for: limit)
                answer.give(fallback)
            }
            answer.give(await work())
            timer.cancel()
        }
    }
}

/// A continuation resumed by whichever of two gets to it first.
private nonisolated final class Answer<Value: Sendable>: Sendable {
    private let pending: Mutex<CheckedContinuation<Value, Never>?>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        pending = Mutex(continuation)
    }

    func give(_ value: Value) {
        let continuation = pending.withLock { pending in
            defer { pending = nil }
            return pending
        }
        continuation?.resume(returning: value)
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
