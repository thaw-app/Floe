//
//  Updates.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: one shared manager instead of a member of Thaw's AppState. It
//  builds no Sparkle object unless Info.plist has a feed and a public key (UpdateConfiguration).
//  A scheduled update is announced in the status menu item instead of a user notification, and
//  Sparkle shows its own release notes, because Floe has no What's New window. UpdateChannel
//  and the consent and wording logic live in UpdateChannel.swift and UpdateLogic.swift.
//  In the settings process no updater is built: the controls show what the launcher's updater
//  reports and send their changes to it (see UpdatesLink.swift).

import AppKit
import Combine
import Observation
import Sparkle
import ThawUI

@MainActor
@Observable
final class UpdatesManager: NSObject {
    static let shared = UpdatesManager()

    /// False for a build without a feed or a public key; every control hides and nothing runs.
    let isAvailable: Bool

    var canCheckForUpdates = false

    var lastUpdateCheckDate: Date?

    /// Drives the consent sheet in the settings window.
    var isConsentPresented = false

    /// The version a scheduled check found and has not shown yet.
    private(set) var pendingUpdateVersion: String?

    private(set) var hasStartedUpdater = false

    @ObservationIgnored
    private let configuration: UpdateConfiguration

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let consent: UpdateConsent

    /// Mirrors Sparkle's KVO publishers into the stored properties above.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    private weak var menuItem: NSMenuItem?

    @ObservationIgnored
    private lazy var updaterController: SPUStandardUpdaterController? = isAvailable && sendToLauncher == nil
        ? SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        : nil

    private var updater: SPUUpdater? {
        updaterController?.updater
    }

    /// Set in the settings process before anything reads the manager: sends a request to the launcher's updater.
    @ObservationIgnored
    var sendToLauncher: ((UpdateRequest) -> Void)?

    /// In the settings process, what the launcher's updater last reported.
    var reported = UpdatesState()

    init(
        configuration: UpdateConfiguration = UpdateConfiguration(info: Bundle.main.infoDictionary),
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.defaults = defaults
        consent = UpdateConsent(defaults: defaults)
        isAvailable = configuration.isConfigured
        super.init()
    }

    /// Whether a manual check can begin now.
    var canCheckNow: Bool {
        if sendToLauncher != nil {
            return isAvailable && reported.canCheckNow
        }
        return isAvailable && UpdateText.canCheckNow(updaterStarted: hasStartedUpdater, updaterCanCheck: canCheckForUpdates)
    }

    /// The channel the user is subscribed to.
    var updateChannel: UpdateChannel {
        get {
            // Backed by UserDefaults, so Observation is registered by hand,
            // like the Sparkle-backed properties below.
            access(keyPath: \.updateChannel)
            if sendToLauncher != nil {
                return UpdateChannel(floeRawValue: reported.channel) ?? .stable
            }
            return UpdateChannel.stored(in: defaults)
        }
        set {
            if let sendToLauncher {
                reported.channel = newValue.rawValue
                sendToLauncher(.setChannel(newValue))
                return
            }
            withMutation(keyPath: \.updateChannel) {
                newValue.store(in: defaults)
            }
            guard hasStartedUpdater else { return }
            updater?.checkForUpdatesInBackground()
        }
    }

    /// Sparkle-backed check/download preferences need explicit access and withMutation calls for Observation tracking.
    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            if sendToLauncher != nil {
                return reported.checks
            }
            return updater?.automaticallyChecksForUpdates ?? false
        }
        set {
            if let sendToLauncher {
                reported.checks = newValue
                sendToLauncher(.setChecks(newValue))
                return
            }
            guard let updater else { return }
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                updater.automaticallyChecksForUpdates = newValue
                if newValue {
                    consent.hasAnswered = true
                }
            }
            if newValue {
                startUpdaterIfNeeded()
            }
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            access(keyPath: \.automaticallyDownloadsUpdates)
            if sendToLauncher != nil {
                return reported.downloads
            }
            return updater?.automaticallyDownloadsUpdates ?? false
        }
        set {
            if let sendToLauncher {
                reported.downloads = newValue
                sendToLauncher(.setDownloads(newValue))
                return
            }
            guard let updater else { return }
            withMutation(keyPath: \.automaticallyDownloadsUpdates) {
                updater.automaticallyDownloadsUpdates = newValue
                if newValue {
                    consent.hasAnswered = true
                }
            }
        }
    }

    /// Called once at launch. Starts the updater only if the user has already answered.
    func performSetup() {
        guard let updater, cancellables.isEmpty else { return }
        // Scrub SUFeedURL defaults that could redirect checks away from Info.plist; the delegate also ignores them.
        _ = updater.clearFeedURLFromUserDefaults()

        // Sparkle's updater is KVO-backed, not @Observable; its publishers
        // mirror into the stored properties Observation can track.
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in
                self?.lastUpdateCheckDate = value
            }
            .store(in: &cancellables)

        if consent.shouldStartUpdater(isConfigured: isAvailable) {
            startUpdaterIfNeeded()
        }
    }

    func startUpdaterIfNeeded() {
        guard let updaterController, !hasStartedUpdater else { return }
        hasStartedUpdater = true
        updaterController.startUpdater()
    }

    @objc func checkForUpdates() {
        if let sendToLauncher {
            sendToLauncher(.check)
            return
        }
        guard let updater else { return }
        #if DEBUG
            // Checking for updates hangs in debug mode, except against a local
            // rehearsal feed (see feedURLString(for:)).
            let debugFeed = defaults.string(forKey: UpdateConfiguration.debugFeedDefaultsKey)
            guard UpdateConfiguration.allowsManualCheck(isDebugBuild: true, debugFeed: debugFeed) else {
                let alert = NSAlert()
                alert.messageText = "Checking for updates is not supported in debug mode."
                alert.runModal()
                return
            }
        #endif
        startUpdaterIfNeeded()
        // Activate the app in case an alert needs to be displayed.
        NSApp.activate()
        updater.checkForUpdates()
    }

    // MARK: Consent

    /// The settings window calls this as it opens.
    static func settingsWillShow() {
        shared.presentConsentIfNeeded()
    }

    private func presentConsentIfNeeded() {
        if consent.shouldAsk(isConfigured: isAvailable) {
            isConsentPresented = true
        }
    }

    /// Same write order as Thaw: the flag, Sparkle's switches, then the updater start.
    func answerConsent(_ choice: AutomaticUpdates) {
        isConsentPresented = false
        if let sendToLauncher {
            reported.checks = choice.checks
            reported.downloads = choice.downloads
            sendToLauncher(.consent(choice))
            return
        }
        consent.hasAnswered = true
        automaticallyChecksForUpdates = choice.checks
        automaticallyDownloadsUpdates = choice.downloads
        startUpdaterIfNeeded()
    }

    // MARK: Status menu

    /// "Check for Updates…" for the status menu, or nil when this build cannot update.
    func makeMenuItem() -> NSMenuItem? {
        guard isAvailable else { return nil }
        let item = NSMenuItem(
            title: UpdateText.menuTitle(pendingVersion: pendingUpdateVersion),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        item.target = self
        menuItem = item
        return item
    }

    private func setPendingUpdateVersion(_ version: String?) {
        pendingUpdateVersion = version
        menuItem?.title = UpdateText.menuTitle(pendingVersion: version)
    }
}

// MARK: UpdatesManager: NSMenuItemValidation

extension UpdatesManager: NSMenuItemValidation {
    func validateMenuItem(_: NSMenuItem) -> Bool {
        canCheckNow
    }
}

// MARK: UpdatesManager: SPUUpdaterDelegate

extension UpdatesManager: SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        // Consent belongs to the app's blocking sheet, never Sparkle's prompt.
        false
    }

    /// Pin the feed to Info.plist so writes to SUFeedURL defaults cannot redirect update checks to a foreign server.
    func feedURLString(for _: SPUUpdater) -> String? {
        #if DEBUG
            // Lets a Debug build rehearse the update flow against a local
            // appcast. Release builds never read it.
            let debugFeed = defaults.string(forKey: UpdateConfiguration.debugFeedDefaultsKey)
            return configuration.feedURLString(isDebugBuild: true, debugFeed: debugFeed)
        #else
            return configuration.feedURLString(isDebugBuild: false, debugFeed: nil)
        #endif
    }

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        UpdateChannel.stored(in: defaults).allowedSparkleChannels
    }
}

// MARK: UpdatesManager: SPUStandardUserDriverDelegate

extension UpdatesManager: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        NSApp.isActive && immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        // Floe usually runs without a window, so an update found in the background waits in the
        // status menu. Choosing the item there brings Sparkle's window forward.
        if !handleShowingUpdate {
            setPendingUpdateVersion(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        setPendingUpdateVersion(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        setPendingUpdateVersion(nil)
    }
}
