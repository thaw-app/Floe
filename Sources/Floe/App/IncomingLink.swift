//
//  IncomingLink.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What a link the system hands Floe asks for, read from the link alone. Any app can open one, so a receiver still
/// checks it against a request of its own. Foundation only: `Fuzzing` compiles this file on Linux.
nonisolated enum IncomingLink: Equatable {
    /// The browser's return from a sign-in.
    case oauth
    /// Thaw's answer about its appearance.
    case thawAppearance
    /// A Raycast link that is not a sign-in's return, which goes on to Raycast.
    case raycast
    case ignored

    static let thawAppearanceHost = "thaw-appearance"
    /// Raycast's return addresses, which Floe holds while a sign-in waits.
    static let redirectSchemes: Set<String> = ["raycast", "com.raycast"]

    init(url: URL, oauthIsParked: Bool) {
        let scheme = url.scheme?.lowercased()
        if let scheme, Self.redirectSchemes.contains(scheme) {
            if Self.isOAuthCallback(url) {
                self = oauthIsParked ? .ignored : .oauth
            } else {
                self = .raycast
            }
            return
        }
        guard scheme == "floe" else {
            self = .ignored
            return
        }
        switch url.host?.lowercased() {
        case Self.thawAppearanceHost:
            self = .thawAppearance
        case "oauth" where !oauthIsParked:
            self = .oauth
        default:
            self = .ignored
        }
    }

    /// `floe://oauth` from Raycast's page, or one of the app return addresses an extension's OAuth app names.
    static func isOAuthCallback(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "floe", "raycast": url.host?.lowercased() == "oauth"
        case "com.raycast": url.host == nil && url.path.lowercased() == "/oauth"
        default: false
        }
    }

    /// The state a sign-in's return carries, which says whose sign-in it answers.
    static func oauthState(of url: URL) -> String? {
        guard isOAuthCallback(url) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
    }
}
