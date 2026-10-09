//
//  AISourcesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// Stands in for the three sources and notes which were asked, so a test can say none but the chosen one was.
final nonisolated class FakeAISources: Sendable {
    enum Name: String, Sendable {
        case api, appleIntelligence, tools
    }

    private let asked = Mutex<[Name]>([])
    /// The sources that fail when asked; the others answer with their own name.
    let failing: Set<Name>

    init(failing: Set<Name> = []) {
        self.failing = failing
    }

    var askedSources: [Name] {
        asked.withLock { $0 }
    }

    private func answer(_ name: Name, emit: AISources.Emit) async throws -> String {
        asked.withLock { $0.append(name) }
        if failing.contains(name) {
            throw ProviderError.failed("\(name.rawValue) failed")
        }
        await emit(name.rawValue)
        return name.rawValue
    }

    var sources: AISources {
        AISources(
            api: { [self] _, _, emit in try await answer(.api, emit: emit) },
            appleIntelligence: { [self] _, emit in try await answer(.appleIntelligence, emit: emit) },
            tools: { [self] _, _, emit in try await answer(.tools, emit: emit) }
        )
    }
}

struct AISourcesTests {
    private static nonisolated let remote = AIAnswer.Choice.api(AIEndpoint(baseURL: "https://openrouter.ai/api/v1", model: "small", apiKey: "key"))
    private static nonisolated let local = AIAnswer.Choice.api(AIEndpoint(baseURL: "http://localhost:11434/v1", model: "small", apiKey: nil))

    private func ask(_ choice: AIAnswer.Choice, localOnly: Bool, fake: FakeAISources) async throws -> String {
        try await AIAnswer.answer("why?", model: nil, choice: choice, localOnly: localOnly, sources: fake.sources) { _ in }
    }

    private func message(_ work: () async throws -> String) async -> String? {
        do {
            _ = try await work()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: The chosen source answers

    @Test(arguments: [
        (AIAnswer.Choice.tools, FakeAISources.Name.tools),
        (.appleIntelligence, .appleIntelligence),
        (remote, .api),
        (local, .api),
    ])
    func theChosenSourceIsTheOnlyOneAsked(choice: AIAnswer.Choice, expected: FakeAISources.Name) async throws {
        let fake = FakeAISources()
        #expect(try await ask(choice, localOnly: false, fake: fake) == expected.rawValue)
        #expect(fake.askedSources == [expected])
    }

    @Test func textIsHandedOnAsItArrives() async throws {
        let pieces = Mutex<[String]>([])
        _ = try await AIAnswer.answer("why?", model: nil, choice: .appleIntelligence, localOnly: true, sources: FakeAISources().sources) { text in
            pieces.withLock { $0.append(text) }
        }
        #expect(pieces.withLock { $0 } == ["appleIntelligence"])
    }

    // MARK: No fallback

    /// Fails if anyone adds a fallback: whichever source is chosen, its failure is the request's
    /// failure and no other source is asked, while every other source stands ready to answer.
    @Test(arguments: [
        (AIAnswer.Choice.tools, FakeAISources.Name.tools),
        (.appleIntelligence, .appleIntelligence),
        (remote, .api),
        (local, .api),
    ])
    func aSourceThatFailsIsNeverReplacedByAnother(choice: AIAnswer.Choice, chosen: FakeAISources.Name) async {
        for localOnly in [false, true] where !localOnly || AskAI.isOnThisMac(choice) {
            let fake = FakeAISources(failing: [chosen])
            let failure = await message { try await ask(choice, localOnly: localOnly, fake: fake) }
            #expect(failure == "\(chosen.rawValue) failed", "the request fails with the chosen source's own message")
            #expect(fake.askedSources == [chosen], "nothing else was tried")
        }
    }

    /// The same rule one level down, for every tool: the one chosen by name answers or the request fails,
    /// whether it is missing or it ran and failed, while every other tool is installed and would answer.
    @Test(arguments: AITool.allCases)
    func aChosenToolIsNeverReplacedByAnother(chosen: AITool) async {
        let others: (String) -> URL? = { $0 == chosen.command ? nil : URL(fileURLWithPath: "/tools/\($0)") }
        let everything: (String) -> URL? = { URL(fileURLWithPath: "/tools/\($0)") }
        let ran = Mutex<[AITool]>([])
        let missing = await message {
            try await AISources.answerWithTool(model: "OpenAI_GPT4o", setup: AIEngine.Setup(tool: chosen), which: others) { engine in
                ran.withLock { $0.append(engine.tool) }
                return "an answer from \(engine.toolName)"
            }
        }
        #expect(missing == AIEngine.missingMessage(for: AIEngine.Setup(tool: chosen)))
        #expect(missing?.contains("\(chosen.command), which is not installed") == true)
        #expect(missing?.contains("Settings › General › AI") == true, "the message says where to change it")
        #expect(ran.withLock { $0 }.isEmpty, "no other tool was run")

        let failing = await message {
            try await AISources.answerWithTool(model: "OpenAI_GPT4o", setup: AIEngine.Setup(tool: chosen), which: everything) { engine in
                ran.withLock { $0.append(engine.tool) }
                throw ShellError("\(engine.toolName) is not signed in")
            }
        }
        #expect(failing == "\(chosen.command) is not signed in", "the request fails with the chosen tool's own message")
        #expect(ran.withLock { $0 } == [chosen], "nothing else was tried")
    }

    @Test func automaticRunsOneToolAndItsFailureIsTheRequests() async {
        let ran = Mutex<[AITool]>([])
        let failing = await message {
            try await AISources.answerWithTool(model: nil, setup: AIEngine.Setup(tool: nil), which: { URL(fileURLWithPath: "/tools/\($0)") }) { engine in
                ran.withLock { $0.append(engine.tool) }
                throw ShellError("not signed in")
            }
        }
        #expect(failing == "not signed in")
        #expect(ran.withLock { $0 } == [.claude], "the next tool in line is not tried after the first fails")
        let none = await message {
            try await AISources.answerWithTool(model: nil, setup: AIEngine.Setup(tool: nil), which: { _ in nil }) { _ in "unreachable" }
        }
        #expect(none == AIEngine.missingMessage)
    }

    @Test func aLocalSourceThatFailsDoesNotReachTheCloud() async {
        let fake = FakeAISources(failing: [.appleIntelligence])
        let failure = await message { try await ask(.appleIntelligence, localOnly: false, fake: fake) }
        #expect(failure == "appleIntelligence failed")
        #expect(!fake.askedSources.contains(.api))
        #expect(!fake.askedSources.contains(.tools))
    }

    @Test func anAPIThatIsNotFilledInFailsWithoutAskingAnything() async {
        for localOnly in [false, true] {
            let fake = FakeAISources()
            let failure = await message { try await ask(.api(nil), localOnly: localOnly, fake: fake) }
            #expect(failure == AIAnswer.incompleteMessage)
            #expect(fake.askedSources.isEmpty)
        }
    }

    // MARK: Only on this Mac

    @Test(arguments: [AIAnswer.Choice.tools, remote])
    func withTheSwitchOnASourceThatIsNotOnThisMacRefusesAndNothingIsAsked(choice: AIAnswer.Choice) async {
        let fake = FakeAISources()
        let failure = await message { try await ask(choice, localOnly: true, fake: fake) }
        #expect(failure == AIAnswer.localOnlyMessage)
        #expect(fake.askedSources.isEmpty, "the question went nowhere, and no local source took it instead")
    }

    /// Whichever tool is chosen, and whatever model it is pointed at, the tools are refused: Floe cannot
    /// see where a tool sends a question, so a model that looks local does not make it local.
    @MainActor
    @Test(arguments: AITool.allCases)
    func withTheSwitchOnEveryToolIsRefused(tool: AITool) async throws {
        let scratch = try ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        settings.aiSource = .tools
        settings.aiTool = tool
        settings.aiToolModels = [tool.rawValue: "ollama/llama3"]
        let choice = AIAnswer.configured(for: nil, settings)
        #expect(choice == .tools)
        #expect(!AskAI.isOnThisMac(choice))
        let fake = FakeAISources()
        let failure = await message { try await ask(choice, localOnly: true, fake: fake) }
        #expect(failure == AIAnswer.localOnlyMessage)
        #expect(fake.askedSources.isEmpty)
        #expect(!AIAnswer.isAvailable(choice: choice, localOnly: true, toolInstalled: { true }, appleIntelligenceReady: { true }))
    }

    @Test(arguments: [(AIAnswer.Choice.appleIntelligence, FakeAISources.Name.appleIntelligence), (local, .api)])
    func withTheSwitchOnASourceOnThisMacStillAnswers(choice: AIAnswer.Choice, expected: FakeAISources.Name) async throws {
        let fake = FakeAISources()
        #expect(try await ask(choice, localOnly: true, fake: fake) == expected.rawValue)
        #expect(fake.askedSources == [expected])
    }

    @Test func theRefusalSaysTheSwitchIsOnAndWhereItIs() {
        #expect(AIAnswer.localOnlyMessage.contains("Only use AI that runs on this Mac"))
        #expect(AIAnswer.localOnlyMessage.contains("Settings › Privacy"))
        #expect(AIAnswer.localOnlyMessage.contains("Settings › General › AI"))
        #expect(AIAnswer.refusal(for: .tools, localOnly: false) == nil)
        #expect(AIAnswer.refusal(for: .appleIntelligence, localOnly: true) == nil)
    }

    @MainActor
    @Test func askAIShowsTheRefusalInItsView() async {
        let fake = FakeAISources()
        let asking = AskAIModel(question: "why?", source: nil) { prompt, emit in
            try await AIAnswer.answer(prompt, model: nil, choice: .tools, localOnly: true, sources: fake.sources, emit: emit)
        }
        await asking.ask().value
        #expect(asking.state == .failed(AIAnswer.localOnlyMessage))
        #expect(asking.answer.isEmpty)
        #expect(fake.askedSources.isEmpty)
    }

    // MARK: Availability

    @Test func aSourceTheSwitchRefusesIsNotAvailable() {
        func available(_ choice: AIAnswer.Choice, localOnly: Bool) -> Bool {
            AIAnswer.isAvailable(choice: choice, localOnly: localOnly, toolInstalled: { true }, appleIntelligenceReady: { true })
        }
        #expect(available(.tools, localOnly: false))
        #expect(available(Self.remote, localOnly: false))
        #expect(!available(.tools, localOnly: true), "extensions and the Ask AI rows are not told AI is there")
        #expect(!available(Self.remote, localOnly: true))
        #expect(available(.appleIntelligence, localOnly: true))
        #expect(available(Self.local, localOnly: true))
    }

    @Test func aSourceThatIsNotReadyIsNotAvailableEitherWay() {
        for localOnly in [false, true] {
            #expect(!AIAnswer.isAvailable(choice: .appleIntelligence, localOnly: localOnly, toolInstalled: { true }, appleIntelligenceReady: { false }))
            #expect(!AIAnswer.isAvailable(choice: .api(nil), localOnly: localOnly, toolInstalled: { true }, appleIntelligenceReady: { true }))
        }
        #expect(!AIAnswer.isAvailable(choice: .tools, localOnly: false, toolInstalled: { false }, appleIntelligenceReady: { true }))
    }

    // MARK: One extension, one source

    @Test func anExtensionPinnedToASourceUsesItAndTheRestUseTheOneInGeneral() {
        let pinned = ["journal": AISource.appleIntelligence]
        #expect(AIAnswer.source(for: "journal", pinned: pinned, general: .tools) == .appleIntelligence)
        #expect(AIAnswer.source(for: "weather", pinned: pinned, general: .tools) == .tools)
        #expect(AIAnswer.source(for: nil, pinned: pinned, general: .api) == .api, "Ask AI has no extension, so it uses General's")
    }

    @MainActor
    @Test func thePinIsReadFromTheSettingsWhereAQuestionIsAnswered() throws {
        let scratch = try ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        settings.aiSource = .tools
        settings.aiSourceByExtension = ["journal": .appleIntelligence]
        #expect(AIAnswer.configured(for: "journal", settings) == .appleIntelligence)
        #expect(AIAnswer.configured(for: "weather", settings) == .tools)
        #expect(AIAnswer.configured(for: nil, settings) == .tools)
        // The switch on Privacy still decides: a pin to the tools is refused like the tools in General.
        #expect(AIAnswer.refusal(for: AIAnswer.configured(for: "weather", settings), localOnly: true) != nil)
        #expect(AIAnswer.refusal(for: AIAnswer.configured(for: "journal", settings), localOnly: true) == nil)
    }

    // MARK: The Privacy page

    @Test func thePrivacyLineSaysASourceIsRefusedWhileTheSwitchIsOn() {
        let tools = PrivacyNetwork.aiLine(source: .tools, baseURL: "", onThisMacOnly: true)
        #expect(tools.contains("does not ask it"))
        for tool in AITool.allCases {
            let named = PrivacyNetwork.aiLine(source: .tools, baseURL: "", tool: tool.command, onThisMacOnly: true)
            #expect(named == "The \(tool.command) tool is chosen, which sends questions to its service. While the switch below is on, Floe does not ask it.")
        }
        let remote = PrivacyNetwork.aiLine(source: .api, baseURL: "https://openrouter.ai/api/v1", onThisMacOnly: true)
        #expect(remote == "openrouter.ai is chosen, which is not on this Mac. While the switch below is on, Floe refuses to ask it, so no question is sent.")
    }

    @Test func thePrivacyLineForASourceOnThisMacIsTheSameEitherWay() {
        for (source, address) in [(AISource.appleIntelligence, ""), (.api, "http://localhost:11434/v1"), (.api, "nonsense")] {
            #expect(PrivacyNetwork.aiLine(source: source, baseURL: address, onThisMacOnly: true) == PrivacyNetwork.aiLine(source: source, baseURL: address))
        }
    }

    @Test func theSwitchIsFoundBySearchingSettings() {
        let entry = SearchIndex.privacyEntries.first { $0.id == "privacy.aiOnThisMacOnly" }
        #expect(entry?.title == "Only use AI that runs on this Mac")
        #expect(entry?.pane == .privacy)
        #expect(entry?.section == "Network Access")
        #expect(SearchIndex.staticEntries.contains { $0.id == "privacy.aiOnThisMacOnly" })
    }
}
