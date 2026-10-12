@testable import Floe
import Testing

struct PanelLifetimeTests {
    @Test func queuesRequestsUntilReady() {
        var lifetime = PanelLifetime()
        #expect(lifetime.request(.show) == [.start])
        #expect(lifetime.request(.builtIn("emoji")) == [])
        #expect(lifetime.ready() == [.send(.request(.show, sequence: 1)), .send(.request(.builtIn("emoji"), sequence: 2))])
    }

    @Test func staleIdleCannotCloseAReopenedPanel() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        _ = lifetime.ready()
        _ = lifetime.request(.toggle)
        #expect(lifetime.idle(sequence: 1) == [])
        #expect(lifetime.idle(sequence: 2) == [.send(.shutdown)])
    }

    @Test func openingDuringExitStartsANewProcessOnlyAfterExit() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.show)
        _ = lifetime.ready()
        _ = lifetime.idle(sequence: 1)
        #expect(lifetime.request(.show) == [])
        #expect(lifetime.exited() == [.start])
        #expect(lifetime.ready() == [.send(.request(.show, sequence: 2))])
    }

    @Test func crashDoesNotReplayAnAlreadyDeliveredCommand() {
        var lifetime = PanelLifetime()
        _ = lifetime.request(.command("sample/run", arguments: nil))
        _ = lifetime.ready()
        #expect(lifetime.exited() == [])
        #expect(lifetime.request(.show) == [.start])
    }

    @Test func hidingAnAbsentPanelDoesNotLaunchIt() {
        var lifetime = PanelLifetime()
        #expect(lifetime.request(.hide) == [])
        #expect(lifetime.ready() == [])
    }
}
