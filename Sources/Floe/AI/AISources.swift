//
//  AISources.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The three things that can answer a prompt, each behind a function so a test can stand in for it.
/// Each is handed the conversation and gives the earlier turns to its source in that source's own way.
nonisolated struct AISources: Sendable {
    typealias Emit = @Sendable (String) async -> Void

    var api: @Sendable (AIEndpoint, AIConversation, Emit) async throws -> String
    var appleIntelligence: @Sendable (AIConversation, Emit) async throws -> String
    /// The conversation, and the model an extension asked for, which Automatic weighs when it picks the tool.
    var tools: @Sendable (AIConversation, String?, Emit) async throws -> String

    /// The real ones: the network, the system's model and the installed tools.
    static let live = AISources(
        api: { endpoint, conversation, emit in
            let request = ChatCompletionStream.request(chatURL: endpoint.chatURL, apiKey: endpoint.apiKey, model: endpoint.model, prompt: conversation.question, earlier: conversation.earlierMessages)
            return try await ChatCompletionStream.run(request, onText: emit)
        },
        appleIntelligence: { conversation, emit in
            try await AppleIntelligence.answer(conversation, emit: emit)
        },
        tools: { conversation, model, emit in
            // A request right after launch waits for the shell, so a tool under nvm or mise is found.
            await LoginEnvironment.load()
            let setup = await MainActor.run { AIEngine.Setup(AppSettings.shared) }
            return try await answerWithTool(model: model, setup: setup, which: { LoginEnvironment.which($0) }, run: { engine in
                Log.ai.info("The command line tool is \(engine.toolName)")
                return try await TextGeneration.run(conversation.replayedPrompt, engine: engine, onText: emit)
            })
        }
    )

    /// Answers with the tool the settings choose. A chosen tool that is missing fails the request with
    /// where to change it: no other tool is tried. `which` and `run` are parameters so a test can stand in.
    /// It runs where its caller does, so neither has to be sent anywhere.
    static nonisolated(nonsending) func answerWithTool(
        model: String?,
        setup: AIEngine.Setup,
        which: (String) -> URL?,
        run: (TextGeneration.Engine) async throws -> String
    ) async throws -> String {
        guard let engine = AIEngine.resolve(model: model, setup: setup, which: which) else {
            throw ShellError(AIEngine.missingMessage(for: setup))
        }
        return try await run(engine)
    }
}

nonisolated extension AIAnswer {
    static let localOnlyMessage = String(
        localized: "“Only use AI that runs on this Mac” is on, and the AI source you chose sends questions elsewhere, so nothing was asked. Turn the switch off under Settings › Privacy, or choose Apple Intelligence or a server on this Mac under Settings › AI.",
        bundle: .floe
    )

    /// Why the chosen source will not be asked, as one message for the person who asked; nil when it may be.
    static func refusal(for choice: Choice, localOnly: Bool) -> String? {
        localOnly && !AskAI.isOnThisMac(choice) ? localOnlyMessage : nil
    }

    /// Answers one prompt with nothing before it, as an extension's `AI.ask` sends.
    @concurrent
    static func answer(
        _ prompt: String,
        model: String?,
        choice: Choice,
        localOnly: Bool,
        sources: AISources = .live,
        emit: AISources.Emit
    ) async throws -> String {
        try await answer(AIConversation(question: prompt), model: model, choice: choice, localOnly: localOnly, sources: sources, emit: emit)
    }

    /// Answers a question with the chosen source, for Ask AI and for an extension's `AI.ask` alike.
    /// It answers or the request fails: nothing else is tried, so a question never leaves by a fallback.
    @concurrent
    static func answer(
        _ conversation: AIConversation,
        model: String?,
        choice: Choice,
        localOnly: Bool,
        sources: AISources = .live,
        emit: AISources.Emit
    ) async throws -> String {
        let started = Date()
        do {
            let text = try await route(conversation, model: model, choice: choice, localOnly: localOnly, sources: sources, emit: emit)
            Log.ai.info("\(choice.logName) answered \(conversation.question.count) characters in \(Log.milliseconds(since: started)) ms")
            return text
        } catch {
            Log.ai.error("\(choice.logName) failed after \(Log.milliseconds(since: started)) ms: \(error.localizedDescription)")
            throw error
        }
    }

    private static func route(
        _ conversation: AIConversation,
        model: String?,
        choice: Choice,
        localOnly: Bool,
        sources: AISources,
        emit: AISources.Emit
    ) async throws -> String {
        if case .api(nil) = choice {
            throw ProviderError.failed(incompleteMessage)
        }
        if let refusal = refusal(for: choice, localOnly: localOnly) {
            throw ProviderError.failed(refusal)
        }
        switch choice {
        case let .api(endpoint?):
            return try await sources.api(endpoint, conversation, emit)
        case .api:
            throw ProviderError.failed(incompleteMessage)
        case .appleIntelligence:
            return try await sources.appleIntelligence(conversation, emit)
        case .tools:
            return try await sources.tools(conversation, model, emit)
        }
    }

    /// Whether the choice can answer at all. `toolInstalled` and `appleIntelligenceReady` are only
    /// asked about the source that was chosen.
    static func isAvailable(choice: Choice, localOnly: Bool, toolInstalled: () -> Bool, appleIntelligenceReady: () -> Bool) -> Bool {
        guard refusal(for: choice, localOnly: localOnly) == nil else { return false }
        switch choice {
        case .tools: return toolInstalled()
        case let .api(endpoint): return endpoint != nil
        case .appleIntelligence: return appleIntelligenceReady()
        }
    }
}

/// The API key, saved for the address it was entered for. A key is read only for that address's origin, so
/// choosing another service, typing another address or importing one sends no key that was saved for elsewhere.
nonisolated struct AIKeys: Sendable {
    var read: @Sendable (_ account: String) -> String?
    var write: @Sendable (_ key: String, _ account: String) -> Void
    var delete: @Sendable (_ account: String) -> Void

    static let keychain = AIKeys(
        read: { Keychain.read(account: $0) },
        write: { Keychain.write($0, account: $1) },
        delete: { Keychain.delete(account: $0) }
    )

    /// The scheme, host and port a key is bound to, such as "https://api.openai.com". Nil for an address that
    /// takes no key: a server on this Mac, or one that cannot be read.
    static func origin(of url: URL?) -> String? {
        guard let url, AIEndpoint.needsKey(url), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let isDefaultPort = url.port == nil || (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80)
        return isDefaultPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(url.port ?? 0)"
    }

    /// The Keychain account of the key saved for one origin. The account with no origin is a key saved before
    /// keys were bound, which `key(for:)` binds on its first read.
    static func account(for origin: String) -> String {
        "\(AIEndpoint.keychainAccount)/\(origin)"
    }

    /// The key saved for the address a base address leads to, or nil when it takes none or none was saved for it.
    /// A key saved before keys were bound is never read here: it is bound once, at launch and before an import, so
    /// an address chosen or half typed later can't take it.
    func key(for baseURL: String) -> String? {
        guard let origin = Self.origin(of: AIEndpoint.chatURL(baseURL: baseURL)) else { return nil }
        return read(Self.account(for: origin))
    }

    /// Saves the key typed for an address, or removes it when the field is emptied. An address that takes no key
    /// keeps nothing.
    func save(_ key: String, for baseURL: String) {
        guard let origin = Self.origin(of: AIEndpoint.chatURL(baseURL: baseURL)) else { return }
        if key.isEmpty {
            delete(Self.account(for: origin))
        } else {
            write(key, Self.account(for: origin))
        }
    }

    /// At launch, and before an import replaces the address: a key saved before keys were bound goes with the address
    /// in use now, as it did until then. When that address takes no key, or has one of its own, the earlier key is removed,
    /// since it would otherwise be bound to the address the import brings.
    func bindEarlierKey(inUseWith baseURL: String) {
        if let origin = Self.origin(of: AIEndpoint.chatURL(baseURL: baseURL)), read(Self.account(for: origin)) == nil {
            bindEarlierKey(to: origin)
        } else if read(AIEndpoint.keychainAccount) != nil {
            Log.ai.notice("An API key saved before keys were bound to an address was removed, since the address in use does not take it")
            delete(AIEndpoint.keychainAccount)
        }
    }

    /// Moves a key saved before keys were bound to `origin`, the address it is in use with. The earlier one stays
    /// until the copy reads back, so a write that fails loses no key.
    private func bindEarlierKey(to origin: String) {
        guard let earlier = read(AIEndpoint.keychainAccount) else { return }
        write(earlier, Self.account(for: origin))
        guard read(Self.account(for: origin)) == earlier else { return }
        delete(AIEndpoint.keychainAccount)
    }
}
