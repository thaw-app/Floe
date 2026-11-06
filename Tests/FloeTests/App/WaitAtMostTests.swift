//
//  WaitAtMostTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

@MainActor struct WaitAtMostTests {
    @Test func workThatEndsCallsBackOnceAndTheLimitAddsNothing() async {
        var calls = 0
        await withCheckedContinuation { calledBack in
            waitAtMost(.milliseconds(50), for: {}, then: {
                calls += 1
                if calls == 1 {
                    calledBack.resume()
                }
            })
        }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(calls == 1)
    }

    @Test func workThatNeverEndsStillCallsBackOnceTheLimitHasPassed() async {
        var calls = 0
        // Waits for the call, however long a busy machine takes, rather than a fixed time.
        await withCheckedContinuation { calledBack in
            waitAtMost(.milliseconds(50), for: { try? await Task.sleep(for: .seconds(30)) }, then: {
                calls += 1
                if calls == 1 {
                    calledBack.resume()
                }
            })
        }
        #expect(calls == 1)
    }

    @Test func anAnswerInTimeIsTheWorks() async {
        #expect(await waitAtMost(.seconds(30), otherwise: "late") { "in time" } == "in time")
    }

    @Test func workThatNeverEndsGivesTheFallbackOnceTheLimitHasPassed() async {
        let answer = await waitAtMost(.milliseconds(50), otherwise: "late") {
            try? await Task.sleep(for: .seconds(30))
            return "in time"
        }
        #expect(answer == "late")
    }
}
