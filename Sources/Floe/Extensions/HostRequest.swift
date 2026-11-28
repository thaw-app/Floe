//
//  HostRequest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Foundation

/// Why the app turned a request down, said to the extension as the request's error.
nonisolated struct RequestRefusal: LocalizedError, Sendable {
    let errorDescription: String?
}

/// Something an extension asks the app for and waits on: the host sends `request` with an id, a
/// method and its parameters, and the app sends back `reply` with the same id and a result or an error.
nonisolated enum HostRequest: Sendable, Equatable {
    /// `AI.ask`: one prompt, one answer.
    case askAI(prompt: String, model: String?)
    /// `OAuth.PKCEClient.authorize`: the provider's page, opened in the browser.
    case oauthAuthorize(url: String, state: String, providerName: String)
    /// `OAuth.PKCEClient.getTokens`: the stored tokens, if the extension signed in before.
    case oauthGetTokens(providerId: String)
    /// `OAuth.PKCEClient.setTokens`: what the provider answered the authorization code with, as the JSON text
    /// the Keychain stores. Text, not a dictionary, so the request can cross to another thread.
    case oauthSetTokens(providerId: String, tokens: String)
    /// `OAuth.PKCEClient.removeTokens`.
    case oauthRemoveTokens(providerId: String)

    /// Whether the OAuth broker answers this rather than `answer`.
    /// Reading or removing saved tokens, which changes nothing outside Floe and starts no sign-in.
    var asksOnlyForTokens: Bool {
        switch self {
        case .oauthGetTokens, .oauthRemoveTokens: true
        default: false
        }
    }

    var isOAuth: Bool {
        switch self {
        case .oauthAuthorize, .oauthGetTokens, .oauthSetTokens, .oauthRemoveTokens:
            true
        case .askAI, .selectedText, .selectedFinderItems, .clipboardRead, .frontmostApplication, .defaultApplication, .applications, .browserTabs, .browserScript, .windowManagement:
            false
        }
    }

    /// `getSelectedText`: the frontmost app's selected text.
    case selectedText
    /// `getSelectedFinderItems`: the Finder's selection, when Finder is frontmost.
    case selectedFinderItems
    /// `Clipboard.read`: the pasteboard as text, HTML and file. With an offset, a copy before it, which the session
    /// answers from Floe's history.
    case clipboardRead(offset: Int)
    /// `getFrontmostApplication`: the app the user is in, as name, path and bundle id.
    case frontmostApplication
    /// `getDefaultApplication`: the app that would open the file at a path.
    case defaultApplication(path: String)
    /// `getApplications(path)` and `Action.OpenWith`: every app that can open the file, the default first.
    case applications(path: String)
    /// `BrowserExtension.getTabs()`.
    case browserTabs
    /// `BrowserExtension.getContent()`: the runtime's script for the page, run in a tab.
    case browserScript(javascript: String, tabID: Int?)
    /// The `WindowManagement` methods: desktops, windows, and moving one.
    case windowManagement(WindowManagement.Request)

    /// Nil for a method the app doesn't know, or one whose parameters are missing.
    init?(method: String, params: [String: Any]) {
        if let family = Self.families[String(method.prefix { $0 != "." })] {
            guard let request = family(method, params) else { return nil }
            self = request
            return
        }
        switch method {
        case "ai.ask":
            guard let prompt = params["prompt"] as? String else { return nil }
            self = .askAI(prompt: prompt, model: params["model"] as? String)
        case "oauth.authorize":
            guard let url = params["url"] as? String,
                  let state = params["state"] as? String,
                  let providerName = params["providerName"] as? String
            else { return nil }
            self = .oauthAuthorize(url: url, state: state, providerName: providerName)
        case "oauth.getTokens":
            guard let providerId = params["providerId"] as? String else { return nil }
            self = .oauthGetTokens(providerId: providerId)
        case "oauth.setTokens":
            // Sorted keys, so the same tokens are the same text.
            guard let providerId = params["providerId"] as? String,
                  let tokens = params["tokens"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: tokens, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8)
            else { return nil }
            self = .oauthSetTokens(providerId: providerId, tokens: text)
        case "oauth.removeTokens":
            guard let providerId = params["providerId"] as? String else { return nil }
            self = .oauthRemoveTokens(providerId: providerId)
        case "selectedText":
            self = .selectedText
        case "selectedFinderItems":
            self = .selectedFinderItems
        case "clipboard.read":
            self = .clipboardRead(offset: max(params["offset"] as? Int ?? 0, 0))
        default:
            return nil
        }
    }

    /// Methods read apart from the main switch, by the word before their first dot, so it stays readable.
    private static let families: [String: @Sendable (String, [String: Any]) -> HostRequest?] = [
        "environment": environmentRequest,
        "browser": browserRequest,
        "windowManagement": { WindowManagement.Request(method: $0, params: $1).map(HostRequest.windowManagement) },
    ]

    /// The `environment.*` methods.
    private static func environmentRequest(method: String, params: [String: Any]) -> HostRequest? {
        switch method {
        case "environment.frontmostApplication":
            return .frontmostApplication
        case "environment.getDefaultApplication":
            guard let path = params["path"] as? String else { return nil }
            return .defaultApplication(path: path)
        case "environment.getApplications":
            guard let path = params["path"] as? String else { return nil }
            return .applications(path: path)
        default:
            return nil
        }
    }

    /// The `BrowserExtension` methods.
    private static func browserRequest(method: String, params: [String: Any]) -> HostRequest? {
        switch method {
        case "browser.tabs":
            return .browserTabs
        case "browser.script":
            guard let javascript = params["javascript"] as? String else { return nil }
            return .browserScript(javascript: javascript, tabID: params["tabId"] as? Int)
        default:
            return nil
        }
    }

    /// Answers a request with the real system: the user's settings, the login shell's environment
    /// and the installed tools. Text that arrives before the whole answer goes to `emit`.
    @concurrent @Sendable
    static func answer(_ request: HostRequest, emit: @Sendable (String) async -> Void) async throws -> Any {
        switch request {
        case let .askAI(prompt, model):
            // An extension's prompt: one question, with nothing before it (see AISources.swift).
            let asking = AIAnswer.askingExtension
            let (choice, localOnly) = await MainActor.run { (AIAnswer.configured(for: asking), AppSettings.shared.aiOnThisMacOnly) }
            return try await AIAnswer.answer(prompt, model: model, choice: choice, localOnly: localOnly, emit: emit)
        case .oauthAuthorize, .oauthGetTokens, .oauthSetTokens, .oauthRemoveTokens:
            // Answered by the OAuth broker, through the same reply channel (see Session+Requests.swift).
            throw OAuthError.unknownRequest
        case .selectedText:
            return try await SelectedText.current()
        case .selectedFinderItems:
            return try await FinderSelection.current()
        case .clipboardRead:
            return await MainActor.run { PasteboardContent.read() }
        case .frontmostApplication:
            return await MainActor.run { Self.frontmostApplication() } as Any
        case let .defaultApplication(path):
            return await MainActor.run { Self.defaultApplication(forFileAt: path) } as Any
        case let .applications(path):
            return Self.applications(forFileAt: path)
        case .browserTabs, .browserScript:
            return try await answerBrowser(request)
        case let .windowManagement(request):
            return try await WindowManagement.answer(request)
        }
    }

    /// The `BrowserExtension` requests, answered by the browser in front.
    private static func answerBrowser(_ request: HostRequest) async throws -> Any {
        if case let .browserScript(javascript, tabID) = request {
            return try await BrowserExtensionBridge.run(javascript, tabID: tabID, frontmost: frontmostBundleID(), run: AppleScript.execute)
        }
        return try await BrowserExtensionBridge.tabs(frontmost: frontmostBundleID(), run: AppleScript.execute)
    }

    /// The frontmost app's bundle id, which says which browser BrowserExtension reads.
    private static func frontmostBundleID() async -> String? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    }

    /// The frontmost app as the API's Application: name, path and bundle id. Nil when nothing is
    /// in front or it has no bundle, which the caller answers with its own stand-in.
    @MainActor
    private static func frontmostApplication() -> [String: String]? {
        guard let app = NSWorkspace.shared.frontmostApplication, let url = app.bundleURL else { return nil }
        return application(at: url, name: app.localizedName)
    }

    /// An app as the API's Application. Extensions tell apps apart by `bundleId`, so it is there whenever the bundle has one.
    static func application(at url: URL, name: String? = nil) -> [String: String] {
        var application = ["name": name ?? url.deletingPathExtension().lastPathComponent, "path": url.path]
        application["bundleId"] = Bundle(url: url)?.bundleIdentifier
        return application
    }

    /// The apps that can open the file, the one the system would use first, each once.
    nonisolated static func applications(forFileAt path: String) -> [[String: String]] {
        let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: file)
        let urls = (preferred.map { [$0] } ?? []) + NSWorkspace.shared.urlsForApplications(toOpen: file).filter { $0 != preferred }
        return urls.map { application(at: $0) }
    }

    /// The app the system would open the file with. Nil when it names none, which the caller
    /// answers with the Finder, as the system itself does.
    @MainActor
    private static func defaultApplication(forFileAt path: String) -> [String: String]? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return NSWorkspace.shared.urlForApplication(toOpen: url).map { application(at: $0) }
    }
}
