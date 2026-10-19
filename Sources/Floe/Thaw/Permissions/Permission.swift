//
//  Permission.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: the system calls are made directly instead of through ThawAX and
//  ThawCapture, opening System Settings is injectable so tests never launch it, and the
//  Screen Recording permission is left out because Floe captures nothing.
//  The copy describes what Floe does with each grant.

import ApplicationServices
import Cocoa
import Combine
import SwiftUI

// MARK: - Permission

/// Checks and requests one app permission.
@MainActor
@Observable
class Permission: Identifiable {
    private(set) var hasPermission = false {
        didSet {
            // The polling timer reassigns this every few seconds; only an
            // actual transition should notify the owner.
            guard oldValue != hasPermission else { return }
            if hasPermission {
                wasDeclined = false
                awaitingPromptAnswer = false
            }
            onChange?()
        }
    }

    /// A shown prompt remained ungranted, so surfaces may offer System Settings instead of waiting.
    /// Persists across ungranted requests until a grant; requests without a prompt open Settings directly and do not count.
    private(set) var wasDeclined = false

    /// Set by a request that showed the system prompt, cleared by the poll
    /// tick that turns it into wasDeclined or by the grant landing.
    private var awaitingPromptAnswer = false

    /// Notify owners only after a changed permission value is stored.
    @ObservationIgnored
    var onChange: (() -> Void)?

    /// Names the permission in what Floe stores, where the title would change with the language.
    let key: String

    let title: String

    let iconName: String

    let iconColor: Color

    let details: [String]

    /// One line for a card in the welcome, where the details would not fit.
    let summary: String

    /// Whether menu bar search needs this permission. Floe itself runs without any of them.
    let isRequired: Bool

    /// The URL of the settings pane to open.
    private let settingsURL: URL?

    /// The function that checks permissions.
    private let check: () -> Bool

    /// Reports granted, then prompted; back off on declined prompts and fall back to System Settings when no prompt appeared.
    private let request: (@escaping @MainActor @Sendable (Bool, Bool) -> Void) -> Void

    /// Opens the settings pane. Injectable so tests do not launch System Settings.
    private let openURL: (URL) -> Void

    /// Observer that runs on a timer to check permissions.
    @ObservationIgnored
    private var timerCancellable: AnyCancellable?

    /// Refreshes permission state when the app becomes active after opening
    /// settingsURL (e.g. returning from System Settings).
    @ObservationIgnored
    private var settingsReturnCancellable: AnyCancellable?

    /// Injectable polling interval lets tests avoid real-time waits; production uses the default.
    @ObservationIgnored
    private let pollInterval: TimeInterval

    /// Stop polling after consecutive ungranted ticks (three minutes by default) to avoid session-long wakes after decline.
    /// Settings-return observation catches late grants; visible permission surfaces can rearm polling.
    @ObservationIgnored
    private let ungrantedPollBudget: Int

    /// Consecutive ungranted ticks since the poll was (re)armed.
    @ObservationIgnored
    private var ungrantedTickCount = 0

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - key: A name for the permission that never changes.
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - isRequired: A Boolean value that indicates if menu bar search needs this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions, reporting whether
    ///     access was granted and whether a system prompt was surfaced.
    ///   - openURL: Opens the settings pane. Defaults to the workspace.
    ///   - pollInterval: Seconds between ungranted re-checks. Defaults to 3.
    ///   - ungrantedPollBudget: Consecutive ungranted re-checks before the
    ///     poll stops itself. At the default interval, three minutes.
    init(
        key: String,
        title: String,
        iconName: String,
        iconColor: Color,
        details: [String],
        summary: String? = nil,
        isRequired: Bool,
        settingsURL: URL?,
        check: @escaping () -> Bool,
        request: @escaping (@escaping @MainActor @Sendable (Bool, Bool) -> Void) -> Void,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        pollInterval: TimeInterval = 3,
        ungrantedPollBudget: Int = 60
    ) {
        self.key = key
        self.title = title
        self.iconName = iconName
        self.iconColor = iconColor
        self.details = details
        self.summary = summary ?? details.first ?? ""
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.check = check
        self.request = request
        self.openURL = openURL
        self.pollInterval = pollInterval
        self.ungrantedPollBudget = ungrantedPollBudget
        self.hasPermission = check()
        configureCancellables()
    }

    /// Poll until granted or the ungranted budget expires; avoid needless wakes after grant or decline.
    private func configureCancellables() {
        ungrantedTickCount = 0
        // Check before subscribing; a setup-time sink tick cannot cancel a subscription that has not been stored yet.
        handlePollTick()
        guard !hasPermission, ungrantedTickCount < ungrantedPollBudget else { return }
        timerCancellable = Timer.publish(every: pollInterval, tolerance: 0.5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                // Safe: the timer is on the main run loop.
                MainActor.assumeIsolated { self?.handlePollTick() }
            }
    }

    /// Publish only transitions and stop at the ungranted budget; internal access lets tests drive ticks without timers.
    func handlePollTick() {
        let granted = check()
        setHasPermissionIfChanged(granted)
        if granted {
            stopCheck()
            return
        }
        ungrantedTickCount += 1
        if awaitingPromptAnswer {
            awaitingPromptAnswer = false
            wasDeclined = true
        }
        if ungrantedTickCount >= ungrantedPollBudget {
            timerCancellable?.cancel()
            timerCancellable = nil
            // Keep the settings-return observer armed to catch grants after the polling budget expires.
        }
    }

    /// Visible onboarding or permission surfaces rearm polling through AppPermissions, not for the lifetime of a declined prompt.
    func resumePollingIfNeeded() {
        guard !hasPermission, timerCancellable == nil else { return }
        configureCancellables()
    }

    /// Whether the ungranted poll is currently armed.
    var isPolling: Bool {
        timerCancellable != nil
    }

    /// Observable notifies on every assignment; skip unchanged values to avoid rerendering permission views on every tick.
    private func setHasPermissionIfChanged(_ granted: Bool) {
        guard granted != hasPermission else { return }
        hasPermission = granted
    }

    /// Open Settings automatically only when no prompt appeared; respect decline until the user requests again or chooses Settings.
    /// Arm preflight-only activation checks either way to recognize later grants without prompting.
    func performRequest() {
        configureCancellables()
        if settingsURL != nil {
            armSettingsReturnObserver()
        }
        request { [weak self] granted, prompted in
            guard let self else { return }
            if granted {
                setHasPermissionIfChanged(true)
                stopCheck()
                return
            }
            if prompted {
                // Prompt requests return before the user's answer; defer the ungranted verdict to the next poll tick.
                awaitingPromptAnswer = true
            } else {
                openSettingsPane()
            }
        }
    }

    /// No-op without a pane URL; call only for no-prompt fallback or an explicit user choice after decline.
    /// Never open Settings alongside a prompt or automatically after decline.
    func openSettingsPane() {
        guard let settingsURL else { return }
        openURL(settingsURL)
    }

    /// Re-checks (preflight only) whenever the app becomes active again, so
    /// a grant made in System Settings is recognized on return.
    private func armSettingsReturnObserver() {
        settingsReturnCancellable?.cancel()
        settingsReturnCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Safe: the publisher hands over on the main run loop.
                MainActor.assumeIsolated { self?.refreshStatus() }
            }
    }

    /// Whether a return to the app re-checks the grant.
    var isObservingSettingsReturn: Bool {
        settingsReturnCancellable != nil
    }

    /// Re-checks current system authorization immediately.
    func refreshStatus() {
        setHasPermissionIfChanged(check())
    }

    /// Stops running the permission check.
    func stopCheck() {
        timerCancellable?.cancel()
        timerCancellable = nil
        settingsReturnCancellable?.cancel()
        settingsReturnCancellable = nil
    }
}

// MARK: - AccessibilityPermission

/// The Accessibility permission, which lets Floe list the menu bar items and
/// open one on the user's behalf.
final class AccessibilityPermission: Permission {
    init() {
        super.init(
            key: "accessibility",
            title: String(localized: "Accessibility", bundle: .floe, comment: "The macOS permission named Accessibility."),
            iconName: "accessibility",
            iconColor: .blue,
            details: [
                String(localized: "Find the items in your menu bar and read their names.", bundle: .floe),
                String(localized: "Open an item's menu when you pick it in the search.", bundle: .floe),
                String(localized: "Search the menus of the app in front, and switch windows.", bundle: .floe),
            ],
            summary: String(localized: "Search the menu bar and app menus, and switch windows.", bundle: .floe, comment: "One line on a permission card in the welcome."),
            isRequired: true,
            // Ungranted AX trust checks always report prompted, so this URL is only for explicit Settings choices and return checks.
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            check: {
                AXIsProcessTrusted()
            },
            request: { completion in
                // Untrusted checks show guidance and return immediately; ungranted means prompted, not necessarily refused.
                // The key is spelled out: Swift imports kAXTrustedCheckOptionPrompt as a mutable global.
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                let granted = AXIsProcessTrustedWithOptions(options)
                completion(granted, !granted)
            }
        )
    }
}
