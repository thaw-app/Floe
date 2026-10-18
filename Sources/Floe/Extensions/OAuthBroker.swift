//
//  OAuthBroker.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Extension sign-in over OAuth PKCE, with the request built in runtime/api/oauth.ts. Temporary: the browser
// returns through raycast.com, whose page opens `floe://oauth` because the state names that scheme.

import AppKit
import Foundation
import Synchronization

/// Why an `oauth.*` request failed, answered to the host as the request's error.
nonisolated enum OAuthError: LocalizedError {
    case timedOut
    case cancelled
    case replaced
    case unknownRequest
    case invalidRedirect(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            String(localized: "Sign-in timed out.", bundle: .floe)
        case .cancelled:
            String(localized: "Sign-in was cancelled.", bundle: .floe)
        case .replaced:
            String(localized: "Sign-in was replaced by a newer request.", bundle: .floe)
        case .unknownRequest:
            String(localized: "Floe can't answer that request.", bundle: .floe)
        case let .invalidRedirect(reason):
            reason
        }
    }
}

/// Answers the host's `oauth.*` requests: interactive sign-in through the `floe://oauth` redirect
/// plus per-extension token storage in the Keychain. Lock-guarded rather than main-actor bound so a
/// session stopping on any thread can cancel its sign-ins.
final nonisolated class OAuthBroker: NSObject, Sendable {
    static let shared = OAuthBroker()

    /// With this on, sign-in through the browser is parked and extensions fall back to a token preference.
    /// While it is off, `IncomingURLRouter` hands `floe://oauth` links to `complete(url:)`.
    static let isParked = false

    /// How long the browser has to come back before the sign-in fails.
    static let timeout: TimeInterval = 600

    private struct Pending: Sendable {
        let extensionName: String
        let state: String
        let resume: @Sendable (Result<String, Error>) -> Void
        let timeout: Task<Void, Never>
    }

    /// Sign-ins waiting for the browser, keyed by extension name and state together.
    private let pending = Mutex<[String: Pending]>([:])
    private let notice: RaycastSignInNotice
    /// How a missing browser is said. The resident sends it to the panel, which shows the HUD.
    private let say = Mutex<@MainActor @Sendable (String) -> Void>({ ThawHUD.show(text: $0) })

    init(notice: RaycastSignInNotice = RaycastSignInNotice()) {
        self.notice = notice
    }

    /// Where the process that runs sign-ins shows what it has to say.
    func say(through say: @escaping @MainActor @Sendable (String) -> Void) {
        self.say.withLock { $0 = say }
    }

    /// Answers a request with a sign-in that is lent, when it is for one. Nil for any other request, which goes
    /// on to the browser sign-in and its storage.
    @concurrent
    static func lent(_ request: HostRequest, extensionName: String, extensionTitle: String, lender: SignInLender = .shared) async -> Any? {
        switch request {
        case let .oauthGetTokens(providerId):
            guard let provider = LentProvider(providerId: providerId) else { return nil }
            return await lender.tokens(for: provider, extensionName: extensionName, extensionTitle: extensionTitle)
        case let .oauthRemoveTokens(providerId):
            guard let provider = LentProvider(providerId: providerId) else { return nil }
            await lender.signOut(of: provider, extensionName: extensionName)
            // With browser sign-in on, the stored tokens are removed too.
            return isParked ? NSNull() : nil
        default:
            return nil
        }
    }

    /// Answers one parsed OAuth request for the session's extension.
    @concurrent
    func perform(_ request: HostRequest, extensionName: String) async throws -> Any {
        switch request {
        case let .oauthAuthorize(urlString, state, providerName):
            guard let url = URL(string: urlString) else { throw OAuthError.invalidRedirect("Missing or invalid param: url") }
            guard await notice.allows(provider: providerName) else { throw OAuthError.cancelled }
            let callback = try await authorize(extensionName: extensionName, url: url, state: state)
            return ["url": callback]
        case let .oauthGetTokens(providerId):
            return tokens(extensionName: extensionName, providerId: providerId).map { $0 as Any } ?? NSNull()
        case let .oauthSetTokens(providerId, tokens):
            saveTokens(tokens, extensionName: extensionName, providerId: providerId)
            return NSNull()
        case let .oauthRemoveTokens(providerId):
            deleteTokens(extensionName: extensionName, providerId: providerId)
            return NSNull()
        case .askAI, .selectedText, .selectedFinderItems, .clipboardRead, .frontmostApplication, .defaultApplication, .applications:
            throw OAuthError.unknownRequest
        }
    }

    /// Opens the provider's page and waits for its `floe://oauth` callback. A newer sign-in from the
    /// same extension replaces this one; cancelling the waiting task, the session stopping, or ten
    /// minutes passing fails it instead.
    func authorize(extensionName: String, url: URL, state: String) async throws -> String {
        let say = say.withLock { $0 }
        await MainActor.run { Browsers.openFromFloe(url, say: say) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(extensionName: extensionName, state: state) { result in
                    continuation.resume(with: result)
                }
                if Task.isCancelled {
                    cancel(extensionName: extensionName, state: state)
                }
            }
        } onCancel: {
            cancel(extensionName: extensionName, state: state)
        }
    }

    /// Fails every sign-in of one extension, when its session stops.
    func cancelAll(for extensionName: String) {
        failPending(for: extensionName, error: OAuthError.cancelled)
    }

    private func pendingKey(extensionName: String, state: String) -> String {
        "\(extensionName)\0\(state)"
    }

    func register(extensionName: String, state: String, resume: @escaping @Sendable (Result<String, Error>) -> Void) {
        let key = pendingKey(extensionName: extensionName, state: state)
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeout))
            guard !Task.isCancelled else { return }
            self?.fail(key: key, error: OAuthError.timedOut)
        }
        // One sign-in per extension: failing what is still waiting and recording the new one happen
        // together, so two racing sign-ins cannot leave one recorded and never answered.
        let replaced: [Pending] = pending.withLock { pending in
            let old = pending.filter { $0.value.extensionName == extensionName }.map(\.key)
                .compactMap { pending.removeValue(forKey: $0) }
            pending[key] = Pending(extensionName: extensionName, state: state, resume: resume, timeout: timeout)
            return old
        }
        for entry in replaced {
            entry.timeout.cancel()
            entry.resume(.failure(OAuthError.replaced))
        }
    }

    func cancel(extensionName: String, state: String) {
        fail(key: pendingKey(extensionName: extensionName, state: state), error: OAuthError.cancelled)
    }

    private func failPending(for extensionName: String, error: Error) {
        let matching = pending.withLock { pending -> [Pending] in
            let keys = pending.filter { $0.value.extensionName == extensionName }.map(\.key)
            return keys.compactMap { pending.removeValue(forKey: $0) }
        }
        for entry in matching {
            entry.timeout.cancel()
            entry.resume(.failure(error))
        }
    }

    private func fail(key: String, error: Error) {
        let entry = pending.withLock { $0.removeValue(forKey: key) }
        guard let entry else { return }
        entry.timeout.cancel()
        entry.resume(.failure(error))
    }

    /// Answers the waiting sign-in whose state the callback carries; anything else is ignored.
    /// Raycast's page names every extension "Extension", so the state alone says whose sign-in it is.
    func complete(url: URL) {
        guard url.scheme == "floe", url.host == "oauth",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let state = items.first(where: { $0.name == "state" })?.value
        else { return }
        let entry = pending.withLock { pending in
            pending.first { $0.value.state == state }.flatMap { pending.removeValue(forKey: $0.key) }
        }
        guard let entry else { return }
        entry.timeout.cancel()
        entry.resume(.success(url.absoluteString))
    }

    // MARK: Token storage

    private func tokenAccount(extensionName: String, providerId: String) -> String {
        "\(extensionName)/oauth/\(providerId)"
    }

    func tokens(extensionName: String, providerId: String) -> [String: Any]? {
        guard let text = Keychain.read(account: tokenAccount(extensionName: extensionName, providerId: providerId)),
              let data = text.data(using: .utf8),
              let tokens = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return tokens
    }

    func saveTokens(_ text: String, extensionName: String, providerId: String) {
        Keychain.write(text, account: tokenAccount(extensionName: extensionName, providerId: providerId))
    }

    func deleteTokens(extensionName: String, providerId: String) {
        Keychain.delete(account: tokenAccount(extensionName: extensionName, providerId: providerId))
    }
}
