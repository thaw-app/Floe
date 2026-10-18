//
//  RedirectSchemeClaim.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Extensions whose OAuth apps return to `raycast://oauth` or `com.raycast:/oauth` are signed in through Floe: while
/// such a sign-in waits, Floe opens those links, and the app that opened them before gets them back after.
@MainActor
final class RedirectSchemeClaim {
    static let shared = RedirectSchemeClaim()
    nonisolated static let schemes: Set<String> = ["raycast", "com.raycast"]
    /// The handlers to give the schemes back to, kept on disk so a crash mid-sign-in still returns them.
    private static let defaultsKey = "RedirectSchemeClaim.previousHandlers"

    struct Handlers {
        var current: (String) -> URL?
        var set: (URL, String) async throws -> Void
    }

    private let handlers: Handlers
    private let defaults: UserDefaults
    private let floe: URL
    /// Sign-ins waiting on each scheme; the last one to end gives it back.
    private var waiting: [String: Int] = [:]

    init(handlers: Handlers = .workspace, defaults: UserDefaults = .standard, floe: URL = Bundle.main.bundleURL) {
        self.handlers = handlers
        self.defaults = defaults
        self.floe = floe
    }

    /// The scheme a sign-in's authorization URL returns to, when it is one of Raycast's.
    nonisolated static func scheme(returningFrom authorization: URL) -> String? {
        let redirect = URLComponents(url: authorization, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "redirect_uri" }?.value
        guard let scheme = redirect.flatMap(URL.init(string:))?.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        return scheme
    }

    func claim(_ scheme: String) async {
        waiting[scheme, default: 0] += 1
        guard waiting[scheme] == 1, let current = handlers.current(scheme), !Self.same(current, floe) else { return }
        var previous = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        previous[scheme] = current.path
        defaults.set(previous, forKey: Self.defaultsKey)
        try? await handlers.set(floe, scheme)
    }

    func release(_ scheme: String) async {
        waiting[scheme, default: 1] -= 1
        guard waiting[scheme] == 0 else { return }
        waiting[scheme] = nil
        await giveBack([scheme])
    }

    /// Gives back what a sign-in that never ended still holds; the resident calls it when it starts.
    func restoreAfterCrash() async {
        await giveBack(Array(Self.schemes))
    }

    private func giveBack(_ schemes: [String]) async {
        var previous = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        for scheme in schemes {
            guard let path = previous.removeValue(forKey: scheme) else { continue }
            try? await handlers.set(URL(fileURLWithPath: path), scheme)
        }
        defaults.set(previous.isEmpty ? nil : previous, forKey: Self.defaultsKey)
    }

    private static func same(_ one: URL, _ other: URL) -> Bool {
        one.standardizedFileURL.resolvingSymlinksInPath() == other.standardizedFileURL.resolvingSymlinksInPath()
    }
}

extension RedirectSchemeClaim.Handlers {
    static let workspace = RedirectSchemeClaim.Handlers(
        current: { scheme in URL(string: "\(scheme):/oauth").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) } },
        set: { app, scheme in try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) }
    )
}
