//
//  OnboardingSequencer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: no tour version, and the recovery stage is the access step alone,
//  shown while a permission is unanswered. The step order and indicator numbers moved here to be tested.

/// The one decision about what the onboarding window shows when it opens.
///
/// One pure function so its callers cannot disagree. The access step
/// rests on the live grants, never a stored flag, because a TCC grant survives
/// a defaults wipe.
enum OnboardingSequencer {
    /// What the onboarding window renders.
    enum Stage: Equatable, Sendable {
        /// The full onboarding sequence, the access step included even when every grant is in place: it shows
        /// what each permission switches on, and which are already granted.
        case onboarding

        /// The access step alone: the welcome was seen, and a permission is neither granted nor declined.
        case access

        /// Nothing to show; the window should not be opened.
        case none
    }

    /// Resolves the stage from the stored flag and the live grants.
    ///
    /// - Parameters:
    ///   - hasSeenOnboarding: Whether the user has finished or skipped the tour once.
    ///   - hasUnanswered: Whether a permission is neither granted nor declined: one a new version
    ///     added, or one that was held and is gone.
    ///   - replayRequested: true when the user asked to see onboarding
    ///     again from Settings, which wins over the stored flag.
    static func stage(
        hasSeenOnboarding: Bool,
        hasUnanswered: Bool = false,
        replayRequested: Bool = false
    ) -> Stage {
        if replayRequested || !hasSeenOnboarding {
            return .onboarding
        }
        return hasUnanswered ? .access : .none
    }

    /// The declined permissions worth remembering: one granted since is forgotten, so losing it asks again.
    static func stillDeclined(_ declined: Set<String>, ungranted: Set<String>) -> Set<String> {
        declined.intersection(ungranted)
    }

    /// Whether a permission that is not granted was never declined.
    static func hasUnanswered(ungranted: Set<String>, declined: Set<String>) -> Bool {
        !ungranted.isSubset(of: declined)
    }
}

/// The screens of the onboarding flow, in order.
enum OnboardingStep: Equatable, Sendable {
    case welcome
    case tour
    case access

    /// A position for the step indicator.
    struct Progress: Equatable, Sendable {
        let step: Int
        let total: Int
    }

    /// The step after this one, or nil when this one ends the flow.
    var next: OnboardingStep? {
        switch self {
        case .welcome: .tour
        case .tour: .access
        case .access: nil
        }
    }

    /// The welcome is not numbered: the steps it leads to are.
    var progress: Progress? {
        switch self {
        case .welcome: nil
        case .tour: Progress(step: 1, total: 2)
        case .access: Progress(step: 2, total: 2)
        }
    }
}
