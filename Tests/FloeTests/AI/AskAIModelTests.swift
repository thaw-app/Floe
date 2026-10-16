//
//  AskAIModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine
@testable import Floe
import Foundation
import Synchronization
import Testing

/// Stands in for an AI source: it answers only when the test lets it, and notes what it was asked.
private final nonisolated class FakeSource: Sendable {
    private struct State {
        var asked: [AIConversation] = []
        var cancellations = 0
        var gates: [AsyncStream<Void>.Continuation] = []
    }

    private let state = Mutex(State())
    /// Sent before the gate, as a source that streams does.
    let early: [String]
    let result: Result<String, ProviderError>

    init(early: [String] = [], result: Result<String, ProviderError> = .success("")) {
        self.early = early
        self.result = result
    }

    /// The question of each request. None of these tests follows one up, so it is all a request carries.
    var prompts: [String] {
        state.withLock { $0.asked.map(\.question) }
    }

    /// Every request as the seam received it.
    var asked: [AIConversation] {
        state.withLock { $0.asked }
    }

    var cancellations: Int {
        state.withLock { $0.cancellations }
    }

    var request: AskAIModel.Request {
        { [self] conversation, emit in
            let (gate, opener) = AsyncStream.makeStream(of: Void.self)
            state.withLock {
                $0.asked.append(conversation)
                $0.gates.append(opener)
            }
            for text in early {
                await emit(text)
            }
            for await _ in gate {
                break
            }
            if Task.isCancelled {
                state.withLock { $0.cancellations += 1 }
                throw CancellationError()
            }
            return try result.get()
        }
    }

    /// Lets every request waiting at the gate go on to its result.
    func open() {
        state.withLock { $0.gates }.forEach { $0.yield() }
    }
}

/// A source that streams what the test sends, when the test sends it.
private final nonisolated class StreamedSource: Sendable {
    private let pipe = AsyncStream.makeStream(of: String.self)
    private let whole = Mutex<String?>(nil)

    var request: AskAIModel.Request {
        { [self] _, emit in
            var all = ""
            for await text in pipe.stream {
                all += text
                await emit(text)
            }
            try Task.checkCancellation()
            return whole.withLock { $0 } ?? all
        }
    }

    func send(_ text: String) {
        pipe.continuation.yield(text)
    }

    /// Ends the stream. The source returns `whole`, or what it streamed.
    func end(with whole: String? = nil) {
        self.whole.withLock { $0 = whole }
        pipe.continuation.finish()
    }
}

/// Stands in for the clock and the parser: the wait between two batches ends when the test says,
/// every parse is noted, and the first parse of one text can be held back to land late.
private final nonisolated class FakeBatching: Sendable {
    private struct State {
        var started: [String] = []
        var waiting: [AsyncStream<Void>.Continuation] = []
        var holding: String?
        var held: CheckedContinuation<Void, Never>?
    }

    private let state: Mutex<State>

    init(holding: String? = nil) {
        state = Mutex(State(holding: holding))
    }

    /// The texts parsed, in the order the parses started.
    var started: [String] {
        state.withLock { $0.started }
    }

    var waiting: Int {
        state.withLock { $0.waiting.count }
    }

    var isHolding: Bool {
        state.withLock { $0.held != nil }
    }

    var parse: AskAIModel.Parse {
        { [self] text, shown in
            let holds = state.withLock { state in
                state.started.append(text)
                guard text == state.holding else { return false }
                state.holding = nil
                return true
            }
            if holds {
                // Not ended by cancellation: a parse that is running cannot be called back.
                await withCheckedContinuation { held in state.withLock { $0.held = held } }
            }
            return await MarkdownContent.parsed(text, reusing: shown)
        }
    }

    var pause: AskAIModel.Pause {
        { [self] in
            let (gate, opener) = AsyncStream.makeStream(of: Void.self)
            state.withLock { $0.waiting.append(opener) }
            for await _ in gate {
                break
            }
        }
    }

    /// The batching interval passes.
    func tick() {
        let waiting = state.withLock { state in
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.finish() }
    }

    /// Lets the parse that was held back return.
    func release() {
        let held = state.withLock { state in
            defer { state.held = nil }
            return state.held
        }
        held?.resume()
    }
}

/// The texts a model showed, in order.
@MainActor
private final class ShownTexts {
    private(set) var texts: [String] = []
    private var watching: AnyCancellable?

    init(_ asking: AskAIModel) {
        watching = asking.$shown.sink { [weak self] in self?.texts.append($0.text) }
    }
}

@MainActor
struct AskAIModelTests {
    private let scratch: ScratchDefaults
    private let source = AskAI.Source(line: "Apple Intelligence, on this Mac", isOnThisMac: true)

    init() throws {
        scratch = ScratchDefaults()
    }

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 2000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func makeLauncher(_ fake: FakeSource, usage: UsageStore? = nil) -> LauncherModel {
        let model = LauncherModel(
            settings: AppSettings(defaults: scratch.defaults),
            usage: usage ?? UsageStore(defaults: scratch.defaults),
            snapshot: CatalogSnapshot(apps: [], commands: []),
            scopes: []
        )
        model.canAskAI = { true }
        model.askAIRequest = fake.request
        return model
    }

    /// What the Actions button of the answer view shows: nothing when the view is not on screen.
    private func actions(of model: LauncherModel) -> [ItemAction?] {
        model.askAI?.actions() ?? []
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    // MARK: The answer's states

    @Test func aQuestionIsAskingUntilTextArrivesThenAnsweringThenFinished() async {
        let fake = FakeSource(early: ["Because ", "of Rayleigh"], result: .success("Because of Rayleigh scattering."))
        let asking = AskAIModel(question: "why is the sky blue", source: source, request: fake.request)
        let task = asking.ask()
        #expect(asking.state == .asking)
        #expect(asking.answer.isEmpty)
        #expect(asking.isWorking)

        await waitFor("the streamed text") { asking.answer == "Because of Rayleigh" }
        #expect(asking.state == .answering)
        #expect(asking.isWorking)

        fake.open()
        await task.value
        #expect(asking.state == .finished)
        #expect(asking.answer == "Because of Rayleigh scattering.", "the whole answer replaces what was streamed")
        #expect(!asking.isWorking)
        #expect(fake.prompts == ["why is the sky blue"])
        #expect(fake.asked == [AIConversation(question: "why is the sky blue")], "one question is sent with nothing before it")
    }

    @Test func aSourceThatDoesNotStreamShowsItsAnswerWhole() async {
        let fake = FakeSource(result: .success("# Whole\n\nAt once."))
        let asking = AskAIModel(question: "q", source: source, request: fake.request)
        let task = asking.ask()
        await waitFor("the request") { fake.prompts.count == 1 }
        #expect(asking.state == .asking, "nothing has arrived, so the view still says it is waiting")
        fake.open()
        await task.value
        #expect(asking.state == .finished)
        #expect(asking.answer == "# Whole\n\nAt once.")
    }

    @Test func aFailureShowsTheSourcesOwnWords() async {
        let fake = FakeSource(result: .failure(.failed(AIAnswer.incompleteMessage)))
        let asking = AskAIModel(question: "q", source: nil, request: fake.request)
        let task = asking.ask()
        await waitFor("the request") { fake.prompts.count == 1 }
        fake.open()
        await task.value
        #expect(asking.state == .failed(AIAnswer.incompleteMessage))
        #expect(asking.answer.isEmpty)
        #expect(!asking.isWorking)
    }

    @Test func askingAgainStartsOverAndDropsTheFirstRequest() async {
        let fake = FakeSource(early: ["first"], result: .success("done"))
        let asking = AskAIModel(question: "q", source: source, request: fake.request)
        asking.ask()
        await waitFor("the first text") { asking.answer == "first" }
        let second = asking.ask()
        #expect(asking.state == .asking)
        #expect(asking.answer.isEmpty, "the first answer is cleared at once")
        await waitFor("the second request") { fake.prompts.count == 2 }
        await waitFor("the first request to be cancelled") { fake.cancellations == 1 }
        fake.open()
        await second.value
        #expect(asking.state == .finished)
        #expect(asking.answer == "done")
    }

    @Test func leavingCancelsTheRequestAndForgetsTheAnswer() async {
        let fake = FakeSource(early: ["partial"], result: .success("never shown"))
        let asking = AskAIModel(question: "q", source: source, request: fake.request)
        let task = asking.ask()
        await waitFor("the first text") { asking.answer == "partial" }
        asking.leave()
        #expect(asking.state == .cancelled)
        #expect(asking.answer.isEmpty)
        await task.value
        #expect(fake.cancellations == 1, "the request in flight was told to stop")
        #expect(asking.state == .cancelled, "a late result changes nothing")
        #expect(asking.answer.isEmpty)
    }

    // MARK: Streaming

    @Test func aStreamingAnswerIsParsedOncePerBatchHoweverManyTokensArrive() async {
        let stream = StreamedSource()
        let batching = FakeBatching()
        let asking = AskAIModel(question: "q", source: source, request: stream.request, parse: batching.parse, pause: batching.pause)
        let task = asking.ask()

        stream.send("# Tides\n\n")
        await waitFor("the first text, drawn at once") { asking.shown.text == "# Tides\n\n" }
        await waitFor("the wait for the next batch") { batching.waiting == 1 }

        let tokens = (1 ... 50).map { "word\($0) " }
        tokens.forEach(stream.send)
        let received = "# Tides\n\n" + tokens.joined()
        await waitFor("every token") { asking.answer == received }
        #expect(batching.started.count == 1, "fifty tokens inside one interval start no parse")
        #expect(asking.shown.text == "# Tides\n\n")

        batching.tick()
        await waitFor("the batch") { asking.shown.text == received }
        #expect(batching.started == ["# Tides\n\n", received], "one parse for the batch, of everything received")
        #expect(asking.shown.blocks == MarkdownParser.blocks(received))

        // Nothing arrived in this interval, so nothing is parsed; the next token is drawn at once again.
        await waitFor("the wait after the batch") { batching.waiting == 1 }
        batching.tick()
        stream.send("end")
        await waitFor("the text after a quiet interval") { asking.shown.text == received + "end" }
        #expect(batching.started.count == 3)

        stream.end()
        await task.value
        #expect(asking.state == .finished)
        #expect(batching.started.count == 3, "the whole answer is what is shown already, so it is not parsed again")
    }

    @Test func updatesArriveInOrderAndEndOnTheWholeAnswer() async {
        let stream = StreamedSource()
        let batching = FakeBatching()
        let asking = AskAIModel(question: "q", source: source, request: stream.request, parse: batching.parse, pause: batching.pause)
        let shown = ShownTexts(asking)
        let task = asking.ask()

        stream.send("one ")
        await waitFor("the first text") { asking.shown.text == "one " }
        stream.send("two ")
        await waitFor("the second token") { asking.answer == "one two " }
        await waitFor("the wait for the next batch") { batching.waiting == 1 }
        batching.tick()
        await waitFor("the second batch") { asking.shown.text == "one two " }
        stream.send("three")
        await waitFor("the third token") { asking.answer == "one two three" }
        #expect(asking.shown.text == "one two ", "the view is a batch behind, and what copy and paste use is not")

        // The interval never passes again: the end of the stream alone brings the rest.
        stream.end(with: "one two three, **four**")
        await task.value
        #expect(asking.state == .finished)
        #expect(asking.answer == "one two three, **four**")
        #expect(asking.shown == MarkdownContent("one two three, **four**"))
        #expect(shown.texts == ["", "", "one ", "one two ", "one two three, **four**"])
    }

    @Test func aFailureAfterSomeTextShowsAllOfTheTextThatArrived() async {
        let fake = FakeSource(early: ["partial ", "answer"], result: .failure(.failed("Cut off.")))
        let batching = FakeBatching()
        let asking = AskAIModel(question: "q", source: source, request: fake.request, parse: batching.parse, pause: batching.pause)
        let task = asking.ask()
        await waitFor("the streamed text") { asking.answer == "partial answer" }
        fake.open()
        await task.value
        #expect(asking.state == .failed("Cut off."))
        #expect(asking.shown.text == "partial answer")
    }

    @Test func aParseThatLandsLateNeverReplacesANewerOne() async throws {
        let stream = StreamedSource()
        let batching = FakeBatching(holding: "old")
        let asking = AskAIModel(question: "q", source: source, request: stream.request, parse: batching.parse, pause: batching.pause)
        let task = asking.ask()

        stream.send("old")
        await waitFor("the parse of the first text, held back") { batching.isHolding }
        let batch = try #require(asking.showing)
        stream.end(with: "old and new")
        await task.value
        #expect(asking.shown.text == "old and new")

        batching.release()
        await batch.value
        #expect(batching.started == ["old", "old and new"])
        #expect(asking.shown.text == "old and new", "the older parse came back last and was dropped")
        #expect(asking.state == .finished)
    }

    @Test func leavingMidStreamLeavesNoLaterUpdate() async throws {
        let stream = StreamedSource()
        let batching = FakeBatching(holding: "first second")
        let asking = AskAIModel(question: "q", source: source, request: stream.request, parse: batching.parse, pause: batching.pause)
        let shown = ShownTexts(asking)
        let task = asking.ask()

        stream.send("first ")
        await waitFor("the first text") { asking.shown.text == "first " }
        await waitFor("the wait for the next batch") { batching.waiting == 1 }
        stream.send("second")
        await waitFor("the second token") { asking.answer == "first second" }
        batching.tick()
        await waitFor("the parse of the batch, held back") { batching.isHolding }
        let batch = try #require(asking.showing)

        asking.leave()
        #expect(asking.shown == .empty)
        #expect(asking.showing == nil)
        batching.release()
        await batch.value
        await task.value

        #expect(asking.state == .cancelled)
        #expect(asking.answer.isEmpty)
        #expect(asking.shown == .empty, "the parse in flight came back to a view that was left")
        #expect(shown.texts == ["", "", "first ", ""])
        #expect(batching.started == ["first ", "first second"], "nothing is parsed after leaving")
    }

    @Test func askingAgainMidStreamDropsTheBatchOfTheFirstRequest() async throws {
        let calls = Mutex(0)
        let batching = FakeBatching(holding: "first")
        let request: AskAIModel.Request = { _, emit in
            let call = calls.withLock { calls in
                calls += 1
                return calls
            }
            guard call == 1 else { return "second" }
            await emit("first")
            // The first request is never answered: it ends when it is cancelled.
            try await Task.sleep(for: .seconds(3600))
            return "never"
        }
        let asking = AskAIModel(question: "q", source: source, request: request, parse: batching.parse, pause: batching.pause)
        let shown = ShownTexts(asking)
        asking.ask()
        await waitFor("the parse of the first text, held back") { batching.isHolding }
        let batch = try #require(asking.showing)

        let second = asking.ask()
        await second.value
        #expect(asking.shown.text == "second")
        batching.release()
        await batch.value
        #expect(asking.state == .finished)
        #expect(asking.shown.text == "second", "text of the request that was replaced is not drawn")
        #expect(shown.texts == ["", "", "", "second"])
    }

    // MARK: In the launcher

    @Test func returnOnTheRowReplacesTheListWithTheAnswerAndEscapeGoesBackWithTheQuery() async throws {
        let fake = FakeSource(result: .success("42"))
        let model = makeLauncher(fake)
        model.query = "ask the answer"
        #expect(model.results.first?.item.title == "Ask AI \u{201C}the answer\u{201D}")
        #expect(try model.handleKey(key(36)))
        let asking = try #require(model.askAI)
        #expect(asking.question == "the answer")
        #expect(!model.panelState.isRootSearch)
        await waitFor("the request") { fake.prompts == ["the answer"] }

        #expect(try model.handleKey(key(53)))
        #expect(model.askAI == nil)
        #expect(model.query == "ask the answer", "the search is as it was left")
        #expect(model.panelState.isRootSearch)
        #expect(asking.state == .cancelled)
        await waitFor("the cancellation") { fake.cancellations == 1 }
    }

    @Test func hidingThePanelCancelsARequestInFlight() async {
        let fake = FakeSource(early: ["par"], result: .success("partial"))
        let model = makeLauncher(fake)
        model.query = "why"
        model.openAskAI("why")
        let asking = model.askAI
        await waitFor("the first text") { asking?.answer == "par" }
        model.panelDidHide()
        #expect(model.askAI == nil)
        #expect(asking?.state == .cancelled)
        #expect(asking?.answer.isEmpty == true)
        await waitFor("the cancellation") { fake.cancellations == 1 }
    }

    @Test func theRowIsNotOfferedByAModelThatCannotAsk() {
        let model = makeLauncher(FakeSource())
        model.canAskAI = { false }
        model.query = "ask why"
        #expect(!model.results.contains { $0.id == "ask-ai" })
    }

    @Test func nothingAboutAQuestionIsStoredOnceTheViewIsLeft() async throws {
        let fake = FakeSource(early: ["a secret answer"], result: .success("a secret answer"))
        let usage = UsageStore(defaults: scratch.defaults)
        let model = makeLauncher(fake, usage: usage)
        model.query = "ask a secret question"
        let row = try #require(model.results.first?.item)
        model.activate(row)
        let asking = try #require(model.askAI)
        await waitFor("the request") { fake.prompts == ["a secret question"] }
        fake.open()
        await waitFor("the answer") { asking.state == .finished }
        // Command-Shift-F on the row would favorite anything else.
        model.toggleFavorite(row)
        model.closeAskAI()
        model.settings.save()

        #expect(model.askAI == nil)
        #expect(asking.answer.isEmpty)
        #expect(usage.records.isEmpty, "opening the row leaves no usage record")
        #expect(model.settings.favorites.isEmpty)
        let stored = scratch.defaults.dictionaryRepresentation()
        #expect(stored.keys.contains("settings"), "the settings were saved, so there is something to look through")
        let text = stored.values.map { value in
            (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: value)
        }.joined()
        #expect(!text.contains("secret"), "neither the question nor the answer is in what Floe saves")
    }

    // MARK: Keys and actions

    @Test func theActionsAreCopyPasteAndAskAgainOnceThereIsAnAnswer() async {
        let fake = FakeSource(result: .success("an answer"))
        let model = makeLauncher(fake)
        #expect(actions(of: model).isEmpty, "there is no menu without the view")
        model.openAskAI("q")
        #expect(actions(of: model).compactMap { $0?.title } == ["Ask Again"], "nothing to copy while waiting")
        await waitFor("the request") { fake.prompts.count == 1 }
        fake.open()
        await waitFor("the answer") { model.askAI?.state == .finished }
        #expect(actions(of: model).compactMap { $0?.title } == ["Copy Answer", "Paste Answer", "Ask Again"])
    }

    @Test func commandRAndTheMenuAskAgain() async throws {
        let fake = FakeSource(result: .success("an answer"))
        let model = makeLauncher(fake)
        model.openAskAI("q")
        await waitFor("the first request") { fake.prompts.count == 1 }
        #expect(try model.handleKey(key(15, .command)))
        await waitFor("the second request") { fake.prompts.count == 2 }
        actions(of: model).compactMap(\.self).last?.run()
        await waitFor("the third request") { fake.prompts.count == 3 }
        #expect(fake.prompts == ["q", "q", "q"])
        model.closeAskAI()
    }

    @Test func returnAsksAFailedQuestionAgain() async throws {
        let fake = FakeSource(result: .failure(.failed("No.")))
        let model = makeLauncher(fake)
        model.openAskAI("q")
        await waitFor("the request") { fake.prompts.count == 1 }
        fake.open()
        await waitFor("the failure") { model.askAI?.state == .failed("No.") }
        #expect(try model.handleKey(key(36)))
        #expect(model.askAI?.state == .asking)
        await waitFor("the second request") { fake.prompts.count == 2 }
        model.closeAskAI()
    }

    @Test func theArrowsScrollTheAnswerAndTypingIsLeftToTheField() throws {
        let model = makeLauncher(FakeSource())
        model.query = "why"
        model.openAskAI("why")
        #expect(try model.handleKey(key(125)))
        #expect(model.askAI?.scroll == AskAIModel.Scroll(id: 1, lines: 1))
        #expect(try model.handleKey(key(126)))
        #expect(model.askAI?.scroll == AskAIModel.Scroll(id: 2, lines: -1))
        #expect(try !model.handleKey(key(0)), "a letter is the field's, where a follow-up is typed")
        #expect(try !model.handleKey(key(8, .command)), "Command-C is left to the selected text")
        #expect(model.query == "why")
        model.closeAskAI()
    }

    @Test func thePanelStateCountsTheAnswerViewAsNotTheRootSearch() {
        let state = LauncherPanelState(
            showingSetup: false, showingCommand: false, menuBarSearch: false, clipboardHistory: false,
            fileSearch: false, queryIsEmpty: true, askingAI: true
        )
        #expect(!state.isRootSearch)
        #expect(!state.isCollapsed(in: .compact), "the answer keeps the full panel in the compact layout")
        #expect(state.contentSize(in: .compact) == LauncherPanelState.fullSize)
    }
}
