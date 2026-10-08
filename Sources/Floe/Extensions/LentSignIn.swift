//
//  LentSignIn.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Synchronization

/// A sign-in the user already has on this Mac that Floe can lend to an extension: GitHub's, from the GitHub CLI.
/// An extension asks for its saved tokens before it starts a sign-in, so one that is lent a token never starts one.
nonisolated enum LentProvider: String, Sendable {
    case github

    /// The provider an extension names, by the id or the name it gives its sign-in.
    init?(providerId: String) {
        self.init(rawValue: providerId.trimmingCharacters(in: .whitespaces).lowercased())
    }

    var name: String {
        "GitHub"
    }

    /// The setting's key for one extension being lent this provider's sign-in.
    func key(for extensionName: String) -> String {
        "\(extensionName)/\(rawValue)"
    }
}

/// Lends a sign-in to an extension the user has allowed, and asks the first time.
final nonisolated class SignInLender: Sendable {
    static let shared = SignInLender()

    /// The token of the sign-in on this Mac: what `gh auth token` prints. Nil when the tool is missing or signed out.
    let token: @Sendable (LentProvider) async -> String?
    /// What the sign-in may do, as `gh auth status` lists it. Empty when that cannot be read.
    let scopes: @Sendable (LentProvider) async -> [String]
    /// Asks the user whether the extension may use the sign-in, naming what the sign-in may do.
    let asks: @Sendable (_ extensionTitle: String, LentProvider, _ scopes: [String]) async -> Bool
    let isAllowed: @Sendable (String) async -> Bool
    let allow: @Sendable (String) async -> Void
    let takeBack: @Sendable (String) async -> Void
    /// The extensions told no since Floe started, so the question is not put at every command.
    private let declined = Mutex<Set<String>>([])

    init(
        token: @escaping @Sendable (LentProvider) async -> String? = SignInLender.cliToken,
        scopes: @escaping @Sendable (LentProvider) async -> [String] = SignInLender.cliScopes,
        asks: @escaping @Sendable (String, LentProvider, [String]) async -> Bool = { title, provider, scopes in
            await MainActor.run { SignInLender.ask(extensionTitle: title, provider: provider, scopes: scopes) }
        },
        isAllowed: @escaping @Sendable (String) async -> Bool = { key in await MainActor.run { AppSettings.shared.lentSignIns.contains(key) } },
        allow: @escaping @Sendable (String) async -> Void = { key in await MainActor.run { _ = AppSettings.shared.lentSignIns.insert(key) } },
        takeBack: @escaping @Sendable (String) async -> Void = { key in await MainActor.run { _ = AppSettings.shared.lentSignIns.remove(key) } }
    ) {
        self.token = token
        self.scopes = scopes
        self.asks = asks
        self.isAllowed = isAllowed
        self.allow = allow
        self.takeBack = takeBack
    }

    /// The tokens to answer an extension with, in the form its client reads. Nil when there is no sign-in to
    /// lend or the user said no.
    func tokens(for provider: LentProvider, extensionName: String, extensionTitle: String, now: Date = Date()) async -> [String: Any]? {
        let key = provider.key(for: extensionName)
        guard !declined.withLock({ $0.contains(key) }), let token = await token(provider) else { return nil }
        if await !isAllowed(key) {
            guard await asks(extensionTitle, provider, scopes(provider)) else {
                declined.withLock { _ = $0.insert(key) }
                return nil
            }
            await allow(key)
        }
        return ["accessToken": token, "updatedAt": now.ISO8601Format()]
    }

    /// The extension signed out: it is not lent the sign-in again until the user allows it anew.
    func signOut(of provider: LentProvider, extensionName: String) async {
        await takeBack(provider.key(for: extensionName))
    }

    @concurrent
    static func cliToken(_: LentProvider) async -> String? {
        guard let result = try? await Shell.run(tool: "gh", ["auth", "token"], timeout: 10), result.succeeded else { return nil }
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// `gh` prints its status on standard output or on standard error, depending on its version.
    @concurrent
    static func cliScopes(_: LentProvider) async -> [String] {
        guard let result = try? await Shell.run(tool: "gh", ["auth", "status"], timeout: 10) else { return [] }
        return scopes(inStatus: result.output + "\n" + result.errorOutput)
    }

    /// The scopes in what `gh auth status` prints: those of the account in use, in the order given.
    /// Empty when the line is missing, says none, or holds nothing that reads as a scope.
    static func scopes(inStatus status: String) -> [String] {
        let lines = status.split(whereSeparator: \.isNewline)
        // With several accounts signed in, the token Floe lends is the active one's.
        let active = lines.firstIndex { $0.contains("Active account: true") } ?? lines.startIndex
        guard let line = lines[active...].first(where: { $0.contains("Token scopes:") }) else { return [] }
        return line.matches(of: #/'([A-Za-z0-9_:.\-]+)'/#).map { String($0.1) }
    }

    /// What the question says under its title: the scopes by name when they are known, and in general words when not.
    static func explanation(scopes: [String]) -> String {
        guard !scopes.isEmpty else {
            return String(localized: "Floe can lend this extension the sign-in of the GitHub CLI on this Mac. The extension can then do everything that sign-in may, which is often more than the extension asks for. You can take this back on the extension’s page in Settings.", bundle: .floe)
        }
        let list = scopes.joined(separator: ", ")
        return String(localized: "Floe can lend this extension the sign-in of the GitHub CLI on this Mac. This sign-in may: \(list). The extension can then do all of it, which is often more than the extension asks for. You can take this back on the extension’s page in Settings.", bundle: .floe, comment: "The placeholder is a list of GitHub permission names, such as gist, repo, workflow.")
    }

    @MainActor
    static func ask(extensionTitle: String, provider: LentProvider, scopes: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Let “\(extensionTitle)” use your \(provider.name) sign-in?", bundle: .floe, comment: "The first placeholder is an extension's name, the second a service such as GitHub.")
        alert.informativeText = explanation(scopes: scopes)
        alert.addButton(withTitle: String(localized: "Allow", bundle: .floe))
        alert.addButton(withTitle: String(localized: "Don’t Allow", bundle: .floe))
        NSApp.activate()
        return ModalGuard.run { alert.runModal() == .alertFirstButtonReturn }
    }
}
