//
//  OnboardingSequencerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Adapted from Thaw 3's suite to Floe's sequencer: no recovery stage and no tour version.
//  The step order cases are Floe's.

@testable import Floe
import Testing

struct OnboardingSequencerTests {
    private static nonisolated let bools = [false, true]

    @Test(arguments: bools)
    func aReplayRequestAlwaysYieldsOnboarding(hasSeenOnboarding: Bool) {
        #expect(OnboardingSequencer.stage(hasSeenOnboarding: hasSeenOnboarding, replayRequested: true) == .onboarding)
    }

    @Test(arguments: bools)
    func anUnseenTourYieldsTheWholeOnboardingWhateverWasAnswered(hasUnanswered: Bool) {
        // The access step is part of it even with everything granted: it shows what each permission is for.
        #expect(OnboardingSequencer.stage(hasSeenOnboarding: false, hasUnanswered: hasUnanswered) == .onboarding)
    }

    @Test func aSeenTourYieldsNothingWhileEveryPermissionIsAnswered() {
        // A declined permission never reopens the window.
        #expect(OnboardingSequencer.stage(hasSeenOnboarding: true) == .none)
    }

    @Test func aPermissionNobodyAnsweredShowsTheAccessStepAlone() {
        #expect(OnboardingSequencer.stage(hasSeenOnboarding: true, hasUnanswered: true) == .access)
    }

    @Test func aPermissionAddedByANewVersionIsUnanswered() {
        let declined: Set = ["calendar"]
        #expect(!OnboardingSequencer.hasUnanswered(ungranted: ["calendar"], declined: declined))
        #expect(OnboardingSequencer.hasUnanswered(ungranted: ["calendar", "location"], declined: declined))
    }

    @Test func aDeclinedPermissionIsAskedAboutAgainOnlyAfterItWasHeld() {
        // Declined and still not granted: remembered. Granted since: forgotten, so losing it asks again.
        #expect(OnboardingSequencer.stillDeclined(["calendar", "contacts"], ungranted: ["calendar"]) == ["calendar"])
        let afterTheGrant = OnboardingSequencer.stillDeclined(["accessibility"], ungranted: [])
        #expect(OnboardingSequencer.hasUnanswered(ungranted: ["accessibility"], declined: afterTheGrant))
    }

    @Test func nothingIsUnansweredWhenEverythingIsGranted() {
        #expect(!OnboardingSequencer.hasUnanswered(ungranted: [], declined: []))
    }
}

struct OnboardingStepTests {
    @Test func theFlowAlwaysRunsWelcomeTourAccess() {
        #expect(OnboardingStep.welcome.next == .tour)
        #expect(OnboardingStep.tour.next == .access)
        #expect(OnboardingStep.access.next == nil)
    }

    @Test func theTourAndAccessAreNumberedOneAndTwoOfTwoAndTheWelcomeIsNot() {
        #expect(OnboardingStep.welcome.progress == nil)
        #expect(OnboardingStep.tour.progress == OnboardingStep.Progress(step: 1, total: 2))
        #expect(OnboardingStep.access.progress == OnboardingStep.Progress(step: 2, total: 2))
    }
}
