//
//  AIEndpoint.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

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
    /// The Keychain account of a key saved before keys were bound to an address; each key is now saved under it and
    /// its origin (`AIKeys`). Extension secrets are "<extension>/<field>", and no extension is named "floe.ai".
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
            AIKeys.keychain.key(for: settings.aiBaseURL)
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
