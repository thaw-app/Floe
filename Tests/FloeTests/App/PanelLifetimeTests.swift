@testable import Floe
import Testing

struct PanelLifetimeTests {
    /// Initial requests keep their order and receive sequences only after the child can accept them.
    @Test func queuesRequestsUntilReady() {
        var lifetime = PanelLifetime()
        #expect(lifetime.request(.show) == [.start])
        #expect(lifetime.request(.builtIn("emoji")) == [])
        #expect(lifetime.ready() == [.send(.request(.show, sequence: 1)), .send(.request(.builtIn("emoji"), sequence: 2))])
    }

    /// An idle report for the previous request must not dismiss newer user work.
    @Test func staleIdleCannotCloseAReopenedPanel() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        _ = lifetime.ready()
        _ = lifetime.request(.toggle)
        #expect(lifetime.idle(sequence: 1) == [])
        #expect(lifetime.idle(sequence: 2) == [.send(.shutdown)])
    }

    /// Reopening during graceful shutdown waits for exit instead of targeting the dying child.
    @Test func openingDuringExitStartsANewProcessOnlyAfterExit() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        _ = lifetime.ready()
        _ = lifetime.idle(sequence: 1)
        #expect(lifetime.request(.show) == [])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.ready() == [.send(.request(.show, sequence: 2))])
    }

    /// A delivered command may already have side effects, so a crash must not cause replay.
    @Test func crashDoesNotReplayAnAlreadyDeliveredCommand() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.command("sample/run", arguments: nil))
        _ = lifetime.ready()
        #expect(lifetime.exited() == [])
        #expect(lifetime.request(.show) == [.start])
    }

    /// Exhaustion drops the undelivered batch, while a later explicit request starts a fresh batch.
    @Test func repeatedCrashesBeforeReadinessStopAfterThreeAttempts() {
        var lifetime = PanelLifetime()
        #expect(lifetime.request(.show) == [.start])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.exited() == [])
        #expect(lifetime.ready() == [])
        #expect(lifetime.request(.builtIn("emoji")) == [.start])
        #expect(lifetime.ready() == [.send(.request(.builtIn("emoji"), sequence: 1))])
    }

    /// Failures from an earlier successful session do not reduce a new session's retry allowance.
    @Test func reachingReadinessResetsTheStartupFailureBudget() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        _ = lifetime.exited()
        _ = lifetime.exited()
        _ = lifetime.ready()
        _ = lifetime.idle(sequence: 1)
        _ = lifetime.request(.show)
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.exited() == [])
    }

    /// Late readiness and repeated timeout callbacks cannot consume or duplicate queued requests.
    @Test func aTimeoutKeepsQueuedWorkUntilTheReplacementIsReady() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        #expect(lifetime.readinessTimedOut() == [.terminate])
        #expect(!lifetime.isAwaitingReadiness)
        #expect(lifetime.ready() == [], "late readiness cannot consume requests before exit")
        #expect(lifetime.readinessTimedOut() == [], "the same child is terminated only once")
        #expect(lifetime.request(.builtIn("emoji")) == [])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.isAwaitingReadiness)
        #expect(lifetime.ready() == [.send(.request(.show, sequence: 1)), .send(.request(.builtIn("emoji"), sequence: 2))])
        #expect(lifetime.readinessTimedOut() == [], "a ready child is not a startup timeout")
    }

    /// Alternating crashes with hangs cannot bypass the consecutive-start failure limit.
    @Test func timeoutsAndCrashesShareABoundedStartupBudget() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        #expect(lifetime.readinessTimedOut() == [.terminate])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.exited() == [.start], "the second child crashed before readiness")
        #expect(lifetime.readinessTimedOut() == [.terminate])
        #expect(lifetime.exited() == [])
        #expect(lifetime.ready() == [])
        #expect(lifetime.readinessTimedOut() == [])
        #expect(lifetime.request(.toggle) == [.start])
        #expect(lifetime.exited() == [.start], "a later user request gets a fresh budget")
        #expect(lifetime.ready() == [.send(.request(.toggle, sequence: 1))])
    }

    /// Repeated watchdog exits use the same finite allowance as immediate startup crashes.
    @Test func threeHangingChildrenDoNotStartAFourth() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        for attempt in 1 ... 3 {
            #expect(lifetime.readinessTimedOut() == [.terminate])
            #expect(lifetime.exited() == (attempt < 3 ? [.start] : []))
        }
        #expect(lifetime.ready() == [])
    }

    /// A hide request alone must never allocate a new foreground process.
    @Test func hidingAnAbsentPanelDoesNotLaunchIt() {
        var lifetime = PanelLifetime()
        #expect(lifetime.request(.hide) == [])
        #expect(lifetime.ready() == [])
    }

    @Test func theClosedLauncherWaitsForTheNextOpenUnlessMemoryIsShort() {
        #expect(PanelKeepAlive.wait(underPressure: false, environment: [:]) == PanelKeepAlive.closed)
        #expect(PanelKeepAlive.wait(underPressure: true, environment: [:]) == PanelKeepAlive.brief)
        #expect(PanelKeepAlive.wait(underPressure: false, environment: ["FLOE_RESIDENT_BENCH": "30"]) == PanelKeepAlive.brief)
    }
}
