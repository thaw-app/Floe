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

    var forwardOAuth: ((URL) -> Void)?
    var forwardAppearance: ((URL) -> Void)?
    private let oauthIsParked: Bool
    private let appearance: (URL) -> Void
    private let oauth: (URL) -> Void

    init(
        oauthIsParked: Bool = OAuthBroker.isParked,
        appearance: @escaping (URL) -> Void,
        oauth: @escaping (URL) -> Void
    ) {
        self.oauthIsParked = oauthIsParked
        self.appearance = appearance
        self.oauth = oauth
    }

    func install(followsAppearance: Bool = true) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:_:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        // Thaw's answer comes back through the handler, so the follower asks only once it is in place.
        if followsAppearance {
            ThawAppearanceFollower.shared.start()
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor?, _: NSAppleEventDescriptor?) {
        guard let urlString = event?.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString)
        else { return }
        route(url)
    }

    /// Thaw's appearance answer and, unless sign-in is parked, the browser's return. Any other link does nothing.
    func route(_ url: URL) {
        guard url.scheme?.lowercased() == "floe" else { return }
        switch url.host?.lowercased() {
        case ThawAppearanceFollower.callbackHost:
            (forwardAppearance ?? appearance)(url)
        case "oauth" where !oauthIsParked:
            (forwardOAuth ?? oauth)(url)
        default:
            break
        }
    }
}
