//
//  PermissionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  The polling budget cases come from Thaw 3's PermissionPollingBudgetTests; the request,
//  decline and AppPermissions cases are Floe's.

@testable import Floe
import Foundation
import SwiftUI
import Testing

/// Stands in for the system: answers whatever granted holds and records what the permission asked of it.
@MainActor
private final class SystemStub {
    var granted = false
    /// What a request reports back: granted, then prompted.
    var requestAnswer = (granted: false, prompted: true)
    var requestCount = 0
    var openedURLs: [URL] = []

    func makePermission(budget: Int = 10, isRequired: Bool = true, settingsURL: URL? = URL(string: "floe-tests://settings")) -> Permission {
        Permission(
            key: "test",
            title: "Test Permission",
            iconName: "star",
            iconColor: .blue,
            details: ["One detail"],
            isRequired: isRequired,
            settingsURL: settingsURL,
            check: { [unowned self] in granted },
            request: { [unowned self] completion in
                requestCount += 1
                completion(requestAnswer.granted, requestAnswer.prompted)
            },
            openURL: { [unowned self] in openedURLs.append($0) },
            pollInterval: 3600,
            ungrantedPollBudget: budget
        )
    }
}

@MainActor
struct PermissionPollingBudgetTests {
    private let stub = SystemStub()

    @Test func aGrantAfterOnboardingIsRememberedBeforeAccessIsLost() {
        let defaults = MemoryDefaults()
        let decisions = PermissionDecisions(defaults: defaults)
        let permission = stub.makePermission()
        let permissions = AppPermissions(accessibility: permission, others: [], decisions: decisions)
        defer { permissions.stopAllChecks() }
        permissions.declineUngranted()
        #expect(permissions.hasUnanswered == false)
        decisions.decline(["test", "calendar"])

        stub.granted = true
        permission.refreshStatus()
        #expect(decisions.hasUnanswered(["test"]))
        #expect(decisions.hasUnanswered(["calendar"]) == false, "other declines survive")

        stub.granted = false
        permission.refreshStatus()
        let relaunched = PermissionDecisions(defaults: defaults)
        #expect(relaunched.hasUnanswered(["test"]))
        #expect(permissions.hasUnanswered)
    }

    @Test func aGrantAlreadyPresentAtStartupClearsAnEarlierDecline() {
        let defaults = MemoryDefaults()
        let decisions = PermissionDecisions(defaults: defaults)
        decisions.decline(["test"])
        stub.granted = true
        let permissions = AppPermissions(accessibility: stub.makePermission(), others: [], decisions: decisions)
        defer { permissions.stopAllChecks() }
        #expect(decisions.hasUnanswered(["test"]))
    }

    @Test func aGrantedPermissionNeverArmsThePoll() {
        stub.granted = true
        let permission = stub.makePermission()
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
    }

    @Test func thePollStopsItselfOnceTheUngrantedBudgetIsSpent() {
        // The immediate first tick in init already counts, so a budget of 3 leaves two driven ticks.
        let permission = stub.makePermission(budget: 3)
        #expect(permission.isPolling)
        permission.handlePollTick()
        #expect(permission.isPolling)
        permission.handlePollTick()
        #expect(!permission.isPolling)
    }

    @Test func aGrantOnAnyTickStopsThePollAndPublishesTheTransition() {
        let permission = stub.makePermission()
        var changes = 0
        permission.onChange = { changes += 1 }
        #expect(permission.isPolling)

        stub.granted = true
        permission.handlePollTick()
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
        #expect(changes == 1)
    }

    @Test func anUnchangedTickDoesNotNotifyTheOwner() {
        let permission = stub.makePermission()
        var changes = 0
        permission.onChange = { changes += 1 }
        permission.handlePollTick()
        permission.refreshStatus()
        #expect(changes == 0)
    }

    @Test func aLateGrantIsCaughtAfterTheBudgetByResuming() {
        // A budget of 1 is spent by the first check in init.
        let permission = stub.makePermission(budget: 1)
        #expect(!permission.isPolling)

        stub.granted = true
        permission.resumePollingIfNeeded()
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
    }

    @Test func resumingRearmsAnUngrantedPollAndLeavesAGrantedOneAlone() {
        let ungranted = stub.makePermission(budget: 2)
        ungranted.handlePollTick()
        #expect(!ungranted.isPolling)
        ungranted.resumePollingIfNeeded()
        #expect(ungranted.isPolling)

        stub.granted = true
        let granted = stub.makePermission()
        granted.resumePollingIfNeeded()
        #expect(!granted.isPolling)
    }

    @Test func aRevokedGrantIsSeenOnRefresh() {
        stub.granted = true
        let permission = stub.makePermission()
        stub.granted = false
        permission.refreshStatus()
        #expect(!permission.hasPermission)
    }
}

@MainActor
struct PermissionRequestTests {
    private let stub = SystemStub()

    @Test func aRequestGrantedAtOnceStopsEveryCheck() {
        let permission = stub.makePermission()
        stub.requestAnswer = (granted: true, prompted: true)
        permission.performRequest()
        #expect(stub.requestCount == 1)
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
        #expect(!permission.isObservingSettingsReturn)
        #expect(stub.openedURLs.isEmpty)
    }

    @Test func aPromptLeftUnansweredCountsAsDeclinedOnTheNextTick() {
        let permission = stub.makePermission()
        permission.performRequest()
        #expect(!permission.wasDeclined, "the prompt may still be on screen")
        #expect(permission.isObservingSettingsReturn)
        #expect(stub.openedURLs.isEmpty, "System Settings never opens next to a prompt")

        permission.handlePollTick()
        #expect(permission.wasDeclined)
    }

    @Test func aGrantClearsAnEarlierDecline() {
        let permission = stub.makePermission()
        permission.performRequest()
        permission.handlePollTick()
        #expect(permission.wasDeclined)

        stub.granted = true
        permission.handlePollTick()
        #expect(permission.hasPermission)
        #expect(!permission.wasDeclined)
        #expect(!permission.isObservingSettingsReturn)
    }

    @Test func aRequestThatShowsNoPromptOpensSystemSettings() throws {
        let permission = stub.makePermission()
        stub.requestAnswer = (granted: false, prompted: false)
        permission.performRequest()
        #expect(try stub.openedURLs == [#require(URL(string: "floe-tests://settings"))])
        permission.handlePollTick()
        #expect(!permission.wasDeclined, "no prompt was shown, so nothing was declined")
    }

    @Test func aPermissionWithoutASettingsPaneOpensNothing() {
        let permission = stub.makePermission(settingsURL: nil)
        stub.requestAnswer = (granted: false, prompted: false)
        permission.performRequest()
        permission.openSettingsPane()
        #expect(stub.openedURLs.isEmpty)
        #expect(!permission.isObservingSettingsReturn)
    }

    @Test func aRequestRearmsASpentPoll() {
        let permission = stub.makePermission(budget: 2)
        permission.handlePollTick()
        #expect(!permission.isPolling)
        permission.performRequest()
        #expect(permission.isPolling)
    }

    @Test func comingBackToTheAppRechecksTheGrant() async throws {
        let permission = stub.makePermission()
        permission.performRequest()
        stub.granted = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        // The observer hops to the main run loop before it checks.
        for _ in 0 ..< 50 where !permission.hasPermission {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(permission.hasPermission)
    }

    @Test func stoppingTheCheckDisarmsThePollAndTheReturnObserver() {
        let permission = stub.makePermission()
        permission.performRequest()
        permission.stopCheck()
        #expect(!permission.isPolling)
        #expect(!permission.isObservingSettingsReturn)
    }
}

@MainActor
struct AppPermissionsTests {
    private let accessibilitySystem = SystemStub()
    private let calendarSystem = SystemStub()

    private func makePermissions(budget: Int = 10, others: [Permission] = []) -> AppPermissions {
        AppPermissions(accessibility: accessibilitySystem.makePermission(budget: budget), others: others)
    }

    @Test(arguments: [(false, AppPermissions.PermissionsState.missing), (true, .hasAll)])
    func theStateFollowsTheGrant(accessibility: Bool, expected: AppPermissions.PermissionsState) {
        accessibilitySystem.granted = accessibility
        #expect(makePermissions().permissionsState == expected)
    }

    @Test func accessibilityLeadsTheOptionalPermissions() {
        let calendar = calendarSystem.makePermission(budget: 10, isRequired: false)
        let permissions = makePermissions(others: [calendar])
        #expect(permissions.allPermissions.map(\.id) == [permissions.accessibility.id, calendar.id])
    }

    @Test func anOptionalPermissionLeavesTheStateAloneAndCountsTowardEverything() {
        accessibilitySystem.granted = true
        let permissions = makePermissions(others: [calendarSystem.makePermission(budget: 10, isRequired: false)])
        #expect(permissions.permissionsState == .hasAll)
        #expect(!permissions.hasEveryPermission)

        calendarSystem.granted = true
        permissions.refreshPermissionsState()
        #expect(permissions.hasEveryPermission)
    }

    @Test func aGrantSeenOnATickUpdatesTheStateAndReportsTheTransition() {
        let permissions = makePermissions()
        var transitions: [(ObjectIdentifier, Bool)] = []
        permissions.onPermissionTransition = { transitions.append(($0.id, $1)) }

        accessibilitySystem.granted = true
        permissions.accessibility.handlePollTick()
        #expect(permissions.permissionsState == .hasAll)
        #expect(transitions.count == 1)
        #expect(transitions.first?.0 == permissions.accessibility.id)
        #expect(transitions.first?.1 == true)
    }

    @Test func refreshingReadsTheGrantAndRearmsASpentPoll() {
        let permissions = makePermissions(budget: 2)
        permissions.accessibility.handlePollTick()
        #expect(!permissions.accessibility.isPolling)

        permissions.refreshPermissionsState()
        #expect(permissions.permissionsState == .missing)
        #expect(permissions.accessibility.isPolling)

        accessibilitySystem.granted = true
        permissions.refreshPermissionsState()
        #expect(permissions.permissionsState == .hasAll)
    }

    @Test func stoppingAllChecksDisarmsEveryPoll() {
        let permissions = makePermissions()
        permissions.stopAllChecks()
        #expect(permissions.allPermissions.allSatisfy { !$0.isPolling })
    }

    /// Reading the real grant never prompts; only a request does, and no test makes one.
    @Test func theSystemPermissionDescribesWhatFloeUsesItFor() {
        let permissions = AppPermissions()
        #expect(permissions.accessibility.title == "Accessibility")
        #expect(permissions.accessibility.isRequired)
        #expect(permissions.others.map(\.title) == ["Screen Recording", "Folders", "Notifications", "Calendar", "Reminders", "Contacts"])
        #expect(permissions.others.allSatisfy { !$0.isRequired })
        #expect(permissions.allPermissions.map(\.key) == ["accessibility", "screenRecording", "folders", "notifications", "calendar", "reminders", "contacts"])
        #expect(permissions.allPermissions.allSatisfy { !$0.details.isEmpty && !$0.summary.isEmpty })
        permissions.stopAllChecks()
    }
}
