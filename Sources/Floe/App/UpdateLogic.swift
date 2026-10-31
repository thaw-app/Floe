//
//  UpdateLogic.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import ThawUI

/// The update feed and signing key from Info.plist. Updates stay off until both are usable, so a
/// build without a key never starts Sparkle and shows no update controls.
struct UpdateConfiguration: Equatable {
    static let feedURLKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"
    /// A Debug build reads this defaults key for a local appcast to rehearse against.
    static let debugFeedDefaultsKey = "FloeDebugFeedURL"

    let feedURL: String
    let publicKey: String

    init(feedURL: String?, publicKey: String?) {
        self.feedURL = (feedURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicKey = (publicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads a bundle's Info dictionary; nil (as under `swift run`) leaves updates off.
    init(info: [String: Any]?) {
        self.init(feedURL: info?[Self.feedURLKey] as? String, publicKey: info?[Self.publicKeyKey] as? String)
    }

    /// The feed must be an https URL: the appcast names what gets downloaded.
    var hasUsableFeed: Bool {
        guard let url = URL(string: feedURL), url.scheme?.lowercased() == "https", let host = url.host else { return false }
        return !host.isEmpty
    }

    /// An EdDSA public key is 32 bytes, base64 encoded. An empty or placeholder value is not one.
    var hasUsableKey: Bool {
        Data(base64Encoded: publicKey)?.count == 32
    }

    var isConfigured: Bool {
        hasUsableFeed && hasUsableKey
    }

    /// The feed Sparkle should read. Only a Debug build may be pointed at another one.
    func feedURLString(isDebugBuild: Bool, debugFeed: String?) -> String {
        if isDebugBuild, let debugFeed, !debugFeed.isEmpty {
            return debugFeed
        }
        return feedURL
    }

    /// Checking against the real feed hangs in a Debug build, so it needs a rehearsal feed.
    static func allowsManualCheck(isDebugBuild: Bool, debugFeed: String?) -> Bool {
        !isDebugBuild || !(debugFeed ?? "").isEmpty
    }
}

/// Whether the user has answered the update question. Sparkle stays idle until they have.
struct UpdateConsent {
    static let defaultsKey = "hasSeenUpdateConsent"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasAnswered: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }

    /// Asked once, when Settings opens, and only by a build that can update.
    func shouldAsk(isConfigured: Bool) -> Bool {
        isConfigured && !hasAnswered
    }

    /// The updater starts at launch only after an answer; before that a manual check starts it.
    func shouldStartUpdater(isConfigured: Bool) -> Bool {
        isConfigured && hasAnswered
    }
}

/// The words and enabled states of the update controls.
enum UpdateText {
    /// The status menu item, which names an update a scheduled check found and has not shown yet.
    static func menuTitle(pendingVersion: String?) -> String {
        guard let pendingVersion, !pendingVersion.isEmpty else { return String(localized: "Check for Updates…", bundle: .floe) }
        return String(localized: "Update to \(pendingVersion)…", bundle: .floe, comment: "A menu item. The placeholder is a version number such as 1.2.0.")
    }

    /// Before the updater has started, a check is what starts it. Once it runs, Sparkle says
    /// whether another check can begin.
    static func canCheckNow(updaterStarted: Bool, updaterCanCheck: Bool) -> Bool {
        !updaterStarted || updaterCanCheck
    }
}
