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
