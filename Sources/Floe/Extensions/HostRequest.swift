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
        case .askAI, .selectedText, .selectedFinderItems, .clipboardRead, .frontmostApplication, .defaultApplication, .applications, .browserTabs, .browserScript:
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
        case .browserTabs:
            return try await BrowserExtensionBridge.tabs(frontmost: frontmostBundleID(), run: AppleScript.execute)
        case let .browserScript(javascript, tabID):
            return try await BrowserExtensionBridge.run(javascript, tabID: tabID, frontmost: frontmostBundleID(), run: AppleScript.execute)
        }
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

/// What the user chose to answer `AI.ask` with.
enum AISource: String, Codable, CaseIterable {
    /// A command line tool (`AITool`), on the account it is signed in to.
    case tools
    /// An OpenAI-compatible API, with the user's own key.
    case api
    /// The model macOS runs on this Mac.
    case appleIntelligence
}

/// The services Settings fills the API's address in for; anything else is typed by hand.
enum AIService: String, CaseIterable, Identifiable {
    case openAI
    case openRouter
    case zai
    case ollama
    case lmStudio
    case other

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .zai: "Z.ai"
        case .ollama: String(localized: "Ollama, on this Mac", bundle: .floe, comment: "Ollama is the name of an app.")
        case .lmStudio: String(localized: "LM Studio, on this Mac", bundle: .floe, comment: "LM Studio is the name of an app.")
        case .other: String(localized: "Another address", bundle: .floe, comment: "A choice in a list of AI services: one the user types the address of.")
        }
    }

    /// The address the service answers at; nil for one the user types.
    var baseURL: String? {
        switch self {
        case .openAI: AIEndpoint.defaultBaseURL
        case .openRouter: "https://openrouter.ai/api/v1"
        // Z.ai's general API. Its Coding Plan has another address, which Z.ai keeps for the coding tools it supports.
        case .zai: "https://api.z.ai/api/paas/v4"
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .other: nil
        }
    }

    /// The service an address belongs to, so the picker shows what was chosen without storing it.
    static func matching(_ baseURL: String) -> AIService {
        let chat = AIEndpoint.chatURL(baseURL: baseURL)
        return allCases.first { service in
            service.baseURL.flatMap { AIEndpoint.chatURL(baseURL: $0) } == chat && chat != nil
        } ?? .other
    }
}

/// Where an OpenAI-compatible API is, what to ask it for, and the key it takes.
nonisolated struct AIEndpoint: Equatable, Sendable {
    static let defaultBaseURL = "https://api.openai.com/v1"
    /// The key's Keychain account. Extension secrets are "<extension>/<field>", and no extension is named "floe.ai".
    static let keychainAccount = "floe.ai/apiKey"

    let chatURL: URL
    let model: String
    let apiKey: String

    /// Whether an address is a server on this Mac. Everything that asks "local or remote" asks here.
    static func isOnThisMac(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    /// A server on this Mac, such as Ollama or LM Studio, takes requests without a key.
    static func needsKey(_ url: URL?) -> Bool {
        !isOnThisMac(url)
    }

    /// Whether a key may travel to an address: over HTTPS, or to a server on this Mac.
    static func isPrivate(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" || isOnThisMac(url)
    }

    /// Nil until the address and the model are filled in, and the key where the server asks for one.
    init?(baseURL: String, model: String, apiKey: String?) {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chatURL = Self.chatURL(baseURL: baseURL), Self.isPrivate(chatURL), !model.isEmpty else { return nil }
        guard !apiKey.isEmpty || !Self.needsKey(chatURL) else { return nil }
        self.chatURL = chatURL
        self.model = model
        // Settings takes no key for a server on this Mac, so one stored is another service's and stays here.
        self.apiKey = Self.needsKey(chatURL) ? apiKey : ""
    }

    /// What an incomplete setup still needs, as one sentence for Settings; nil when it is complete.
    static func problem(baseURL: String, model: String, apiKey: String?) -> String? {
        if let url = chatURL(baseURL: baseURL), !isPrivate(url) {
            return String(localized: "AI can't answer yet. Its address needs to start with https://, since only a server on this Mac may use http://.", bundle: .floe)
        }
        let address = chatURL(baseURL: baseURL) == nil
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let key = needsKey(chatURL(baseURL: baseURL)) && (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // One whole sentence for each combination, so a translator never gets a fragment.
        return switch (address, model, key) {
        case (false, false, false): nil
        case (true, false, false): String(localized: "AI can't answer yet. It needs an address that starts with http:// or https://.", bundle: .floe)
        case (false, true, false): String(localized: "AI can't answer yet. It needs a model.", bundle: .floe)
        case (false, false, true): String(localized: "AI can't answer yet. It needs an API key.", bundle: .floe)
        case (true, true, false): String(localized: "AI can't answer yet. It needs an address that starts with http:// or https:// and a model.", bundle: .floe)
        case (true, false, true): String(localized: "AI can't answer yet. It needs an address that starts with http:// or https:// and an API key.", bundle: .floe)
        case (false, true, true): String(localized: "AI can't answer yet. It needs a model and an API key.", bundle: .floe)
        case (true, true, true): String(localized: "AI can't answer yet. It needs an address that starts with http:// or https://, a model and an API key.", bundle: .floe)
        }
    }

    /// The chat completions address under a base address like "https://api.openai.com/v1". An
    /// empty address means OpenAI's, and one that already ends in the path is taken as it is.
    static func chatURL(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = defaultBaseURL
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        let path = "/chat/completions"
        guard let url = URL(string: base.hasSuffix(path) ? base : base + path),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        return url
    }
}

/// The choice in Settings › AI, read where a request is answered.
nonisolated enum AIAnswer {
    static let incompleteMessage = String(localized: "AI is set to use an API, but its address, model or key is missing. Fill them in under Settings › AI.", bundle: .floe)

    enum Choice: Equatable {
        case tools
        /// Nil when the API's settings are incomplete.
        case api(AIEndpoint?)
        case appleIntelligence
    }

    /// `key` reads the stored API key; it is only called when the API is the choice, so the
    /// Keychain is left alone otherwise.
    static func choice(source: AISource, baseURL: String, model: String, key: () -> String?) -> Choice {
        switch source {
        case .tools: .tools
        case .api: .api(AIEndpoint(baseURL: baseURL, model: model, apiKey: key()))
        case .appleIntelligence: .appleIntelligence
        }
    }

    @MainActor
    static func configured(_ settings: AppSettings = .shared) -> Choice {
        choice(source: settings.aiSource, baseURL: settings.aiBaseURL, model: settings.aiModel) {
            Keychain.read(account: AIEndpoint.keychainAccount)
        }
    }

    /// Whether extensions should be told AI is there: a tool is installed, the API is filled in, or the Mac's own
    /// model is ready, and the source is not one the "only on this Mac" switch refuses.
    @MainActor
    static var isAvailable: Bool {
        isAvailable(
            choice: configured(),
            localOnly: AppSettings.shared.aiOnThisMacOnly,
            toolInstalled: { AIEngine.isAvailable },
            appleIntelligenceReady: { AppleIntelligence.problem == nil }
        )
    }
}
