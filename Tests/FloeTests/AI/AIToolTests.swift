//
//  AIToolTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Which command line tool answers. `installed` stands in for the PATH, so nothing is looked up or run.
struct AIToolTests {
    private func installed(_ tools: AITool...) -> (String) -> URL? {
        { name in tools.contains { $0.command == name } ? URL(fileURLWithPath: "/tools/\(name)") : nil }
    }

    private func path(_ tool: AITool) -> URL {
        URL(fileURLWithPath: "/tools/\(tool.command)")
    }

    // MARK: Automatic

    @Test func automaticIsWhatItWasWithOnlyClaudeOrCodex() {
        #expect(AIEngine.resolve(model: nil, which: installed(.claude, .codex)) == .claude(executable: path(.claude), model: nil))
        #expect(AIEngine.resolve(model: nil, which: installed(.codex)) == .codex(executable: path(.codex), model: nil))
        #expect(AIEngine.resolve(model: "Anthropic_Claude_Opus", which: installed(.claude)) == .claude(executable: path(.claude), model: "opus"))
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", which: installed(.claude, .codex)) == .codex(executable: path(.codex), model: nil))
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", which: installed(.claude)) == .claude(executable: path(.claude), model: nil))
    }

    @Test func automaticTakesTheFirstInstalledOfClaudeCodexOpencodeAndPi() {
        #expect(AITool.allCases == [.claude, .codex, .opencode, .pi])
        #expect(AIEngine.resolve(model: nil, which: installed(.claude, .codex, .opencode, .pi))?.tool == .claude)
        #expect(AIEngine.resolve(model: nil, which: installed(.codex, .opencode, .pi))?.tool == .codex)
        #expect(AIEngine.resolve(model: nil, which: installed(.opencode, .pi)) == .opencode(executable: path(.opencode), model: nil))
        #expect(AIEngine.resolve(model: nil, which: installed(.pi)) == .pi(executable: path(.pi), model: nil))
        #expect(AIEngine.resolve(model: nil, which: installed()) == nil)
    }

    @Test func anOpenAIModelPrefersCodexOnlyWhenItIsInstalled() {
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", which: installed(.claude, .codex, .opencode, .pi))?.tool == .codex)
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", which: installed(.opencode, .pi))?.tool == .opencode, "without codex the usual order stands")
    }

    // MARK: A tool chosen by name

    @Test(arguments: AITool.allCases)
    func aNamedToolAnswersWhenItIsInstalledWhateverElseIs(tool: AITool) {
        let setup = AIEngine.Setup(tool: tool)
        #expect(AIEngine.resolve(model: nil, setup: setup, which: installed(.claude, .codex, .opencode, .pi))?.tool == tool)
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", setup: setup, which: installed(.claude, .codex, .opencode, .pi))?.tool == tool, "a name is a name: codex is not preferred over it")
        #expect(AIEngine.resolve(model: nil, setup: setup, which: installed(tool))?.executable == path(tool))
    }

    @Test(arguments: AITool.allCases)
    func aNamedToolThatIsNotInstalledIsNotReplaced(tool: AITool) {
        let others: (String) -> URL? = { $0 == tool.command ? nil : URL(fileURLWithPath: "/tools/\($0)") }
        #expect(AIEngine.resolve(model: nil, setup: AIEngine.Setup(tool: tool), which: others) == nil)
        let message = AIEngine.missingMessage(for: AIEngine.Setup(tool: tool))
        #expect(message == "AI is set to answer with \(tool.command), which is not installed. Install it and sign in, or choose another tool under Settings › AI.")
    }

    @Test func withNothingInstalledAutomaticSaysWhatToInstall() {
        #expect(AIEngine.missingMessage(for: AIEngine.Setup(tool: nil)) == "AI needs a command line tool to answer: claude, codex, opencode or pi, installed and signed in.")
    }

    // MARK: The model

    @Test func onlyOpencodeAndPiTakeAModelFromSettings() {
        #expect(AITool.allCases.filter(\.takesModel) == [.opencode, .pi])
    }

    @Test func theModelTypedForAToolIsPassedAsWrittenAndAnEmptyOneLeavesTheDefault() {
        let setup = AIEngine.Setup(tool: nil, models: ["opencode": "  anthropic/claude-sonnet-4-5 ", "pi": "openai/gpt-4o", "claude": "ignored", "codex": "ignored"])
        #expect(AIEngine.resolve(model: nil, setup: setup, which: installed(.opencode)) == .opencode(executable: path(.opencode), model: "anthropic/claude-sonnet-4-5"))
        #expect(AIEngine.resolve(model: nil, setup: setup, which: installed(.pi)) == .pi(executable: path(.pi), model: "openai/gpt-4o"))
        #expect(AIEngine.resolve(model: nil, setup: setup, which: installed(.claude)) == .claude(executable: path(.claude), model: nil))
        #expect(AIEngine.resolve(model: nil, setup: setup, which: installed(.codex)) == .codex(executable: path(.codex), model: nil))
        let blank = AIEngine.Setup(tool: .pi, models: ["pi": "   "])
        #expect(AIEngine.resolve(model: nil, setup: blank, which: installed(.pi)) == .pi(executable: path(.pi), model: nil))
    }

    @Test func theModelAnExtensionAsksForIsNotHandedToOpencodeOrPi() {
        // Raycast's model names are not a provider and model as these tools take them.
        #expect(AIEngine.resolve(model: "Anthropic_Claude_Sonnet", setup: AIEngine.Setup(tool: .opencode), which: installed(.opencode)) == .opencode(executable: path(.opencode), model: nil))
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", setup: AIEngine.Setup(tool: .pi), which: installed(.pi)) == .pi(executable: path(.pi), model: nil))
    }

    @MainActor
    @Test func theSetupIsReadFromTheSettings() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(AIEngine.Setup(settings) == AIEngine.Setup(tool: nil), "Automatic until a tool is chosen")
        settings.aiTool = .pi
        settings.aiToolModels = ["pi": "openai/gpt-4o"]
        #expect(AIEngine.Setup(settings) == AIEngine.Setup(tool: .pi, models: ["pi": "openai/gpt-4o"]))
    }

    // MARK: The picker

    @Test func thePickerListsAutomaticAndTheToolsThatAreInstalled() {
        #expect(AIToolOption.options(chosen: nil, which: installed(.codex, .pi)).map(\.title) == ["Automatic", "codex", "pi"])
        #expect(AIToolOption.options(chosen: nil, which: installed()).map(\.title) == ["Automatic"])
        #expect(AIToolOption.options(chosen: .pi, which: installed(.claude, .pi)).map(\.tool) == [nil, .claude, .pi])
    }

    @Test func aChosenToolThatHasGoneStaysInThePickerMarkedNotInstalled() {
        let options = AIToolOption.options(chosen: .opencode, which: installed(.claude))
        #expect(options.map(\.title) == ["Automatic", "claude", "opencode (not installed)"])
        #expect(options.map(\.tool) == [nil, .claude, .opencode])
        #expect(Set(options.map(\.id)).count == options.count)
    }

    @Test func settingsSaysWhatIsMissing() {
        #expect(AIToolOption.problem(chosen: nil) == "AI can't answer yet. Install claude, codex, opencode or pi and sign in.")
        #expect(AIToolOption.problem(chosen: .pi) == "AI can't answer yet. pi is not installed. Install it and sign in, or choose another tool.")
    }

    // MARK: Who answered

    @Test(arguments: AITool.allCases)
    func theLineUnderAnAnswerNamesTheToolThatAnswered(tool: AITool) {
        let engine = AIEngine.resolve(model: nil, setup: AIEngine.Setup(tool: tool), which: installed(tool))
        #expect(engine?.toolName == tool.command)
        #expect(AskAI.source(for: .tools, tool: engine?.toolName) == AskAI.Source(line: "The \(tool.command) tool, on your account", isOnThisMac: false))
    }

    // MARK: Z.ai

    @Test func zaiIsAServiceWithItsAddressAndNeedsAKey() throws {
        #expect(AIService.zai.title == "Z.ai")
        #expect(AIService.zai.baseURL == "https://api.z.ai/api/paas/v4")
        let address = try #require(AIService.zai.baseURL)
        #expect(AIEndpoint.chatURL(baseURL: address)?.absoluteString == "https://api.z.ai/api/paas/v4/chat/completions")
        #expect(AIEndpoint.needsKey(AIEndpoint.chatURL(baseURL: address)))
        #expect(AIEndpoint(baseURL: address, model: "glm-5.3", apiKey: nil) == nil, "no key, no endpoint")
        #expect(AIEndpoint.problem(baseURL: address, model: "glm-5.3", apiKey: "") == "AI can't answer yet. It needs an API key.")
        let endpoint = try #require(AIEndpoint(baseURL: address, model: "glm-5.3", apiKey: "key"))
        #expect(!AskAI.isOnThisMac(.api(endpoint)))
        #expect(AIAnswer.refusal(for: .api(endpoint), localOnly: true) == AIAnswer.localOnlyMessage)
        #expect(AskAI.source(for: .api(endpoint), tool: nil) == AskAI.Source(line: "api.z.ai", isOnThisMac: false))
        #expect(AIService.allCases.firstIndex(of: .zai) == 2, "beside OpenAI and OpenRouter, before the servers on this Mac")
    }

    @Test func aRequestToZaiIsAStandardChatCompletion() throws {
        let url = try #require(AIEndpoint.chatURL(baseURL: AIService.zai.baseURL ?? ""))
        let request = ChatCompletionStream.request(chatURL: url, apiKey: "key", model: "glm-5.3", prompt: "why?")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
        let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])
        #expect(Set(body.keys) == ["model", "messages", "stream"])
    }
}
