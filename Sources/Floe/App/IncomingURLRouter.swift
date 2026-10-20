//
//  IncomingURLRouter.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Owns the app's one handler for `floe://` links and hands each to what waits on it, by host.
/// Any app can open such a link, so a receiver checks it against a request of its own.
final class IncomingURLRouter: NSObject {
    static let shared = IncomingURLRouter(
        appearance: { ThawAppearanceFollower.shared.receive($0) },
        oauth: { OAuthBroker.shared.complete(url: $0) }
    )

    private let oauthIsParked: Bool
    private let appearance: (URL) -> Void
    private let oauth: (URL) -> Void

    /// Injects URL consumers without registering a system handler or beginning appearance tracking.
    init(
        oauthIsParked: Bool = OAuthBroker.isParked,
        appearance: @escaping (URL) -> Void,
        oauth: @escaping (URL) -> Void
    ) {
        self.oauthIsParked = oauthIsParked
        self.appearance = appearance
        self.oauth = oauth
    }

    /// Registers URL delivery, and starts following Thaw's appearance.
    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:_:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        // Thaw's answer comes back through the handler, so the follower asks only once it is in place.
        ThawAppearanceFollower.shared.start()
        // Floe starting: a sign-in cut short by a crash may still hold Raycast's return addresses.
        Task { await RedirectSchemeClaim.shared.restoreAfterCrash() }
    }

    /// Ignores malformed Apple events before applying the scheme and host routing checks.
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor?, _: NSAppleEventDescriptor?) {
        guard let urlString = event?.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString)
        else { return }
        route(url)
    }

    /// Thaw's appearance answer and, unless sign-in is parked, the browser's return. Any other link does nothing,
    /// but a Raycast link that is not a sign-in's return goes on to Raycast.
    func route(_ url: URL) {
        if let scheme = url.scheme?.lowercased(), RedirectSchemeClaim.schemes.contains(scheme) {
            if OAuthBroker.isCallback(url) {
                if !oauthIsParked {
                    oauth(url)
                }
            } else {
                Self.openInRaycast(url)
            }
            return
        }
        guard url.scheme?.lowercased() == "floe" else { return }
        switch url.host?.lowercased() {
        case ThawAppearanceFollower.callbackHost:
            appearance(url)
        case "oauth" where !oauthIsParked:
            oauth(url)
        default:
            break
        }
    }

    private static func openInRaycast(_ url: URL) {
        guard let raycast = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.raycast.macos") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: raycast, configuration: NSWorkspace.OpenConfiguration())
    }
}
