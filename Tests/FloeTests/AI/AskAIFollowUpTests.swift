//
//  AskAIFollowUpTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Synchronization
import Testing

/// Stands in for an AI source in a conversation: it notes each request as the seam received it and
/// answers with the next of its scripted results, at once or when the test lets it.
private final nonisolated class ScriptedSource: Sendable {
    private struct State {
        var asked: [AIConversation] = []
        var results: [Result<String, ProviderError>]
        var cancellations = 0
        var gates: [AsyncStream<Void>.Continuation] = []
    }

    private let state: Mutex<State>
    /// Sent before the result, as a source that streams does.
    let early: [String]
    /// Whether a request waits for `open()` before it ends.
    let waits: Bool

    init(_ results: [Result<String, ProviderError>], early: [String] = [], waits: Bool = false) {
        state = Mutex(State(results: results))
        self.early = early
        self.waits = waits
    }

    /// Answers each question with "answer to" and the question.
    convenience init() {
        self.init([])
    }

    var asked: [AIConversation] {
        state.withLock { $0.asked }
    }

    var cancellations: Int {
        state.withLock { $0.cancellations }
    }

    var request: AskAIModel.Request {
        { [self] conversation, emit in
            let (gate, opener) = AsyncStream.makeStream(of: Void.self)
            let result = state.withLock { state in
                state.asked.append(conversation)
                state.gates.append(opener)
                return state.results.isEmpty ? .success("answer to \(conversation.question)") : state.results.removeFirst()
            }
            for text in early {
                await emit(text)
            }
            if waits {
                for await _ in gate {
                    break
                }
            }
            if Task.isCancelled {
                state.withLock { $0.cancellations += 1 }
                throw CancellationError()
            }
            return try result.get()
        }
    }

    func open() {
        state.withLock { $0.gates }.forEach { $0.yield() }
    }
}

@MainActor
struct AskAIFollowUpTests {
    private typealias Turn = AIConversation.Turn

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

    private func makeLauncher(_ scripted: ScriptedSource) -> LauncherModel {
        let model = LauncherModel(
            settings: AppSettings(defaults: scratch.defaults),
            usage: UsageStore(defaults: scratch.defaults),
            snapshot: CatalogSnapshot(apps: [], commands: []),
            scopes: []
        )
        model.canAskAI = { true }
        model.askAIRequest = scripted.request
        return model
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    /// Types a follow-up and asks it, waiting for its answer or its failure.
    private func followUp(_ asking: AskAIModel, _ question: String) async throws {
        asking.draft = question
        try await #require(asking.askFollowUp()).value
    }

    // MARK: What a follow-up sends

    @Test func aFollowUpCarriesTheEarlierTurnsToTheRequest() async throws {
        let scripted = ScriptedSource()
        let asking = AskAIModel(question: "how do tides work", source: source, request: scripted.request)
        await asking.ask().value
        try await followUp(asking, "  and why two a day\n")
        try await followUp(asking, "and the Sun?")

        let first = Turn(question: "how do tides work", answer: "answer to how do tides work")
        let second = Turn(question: "and why two a day", answer: "answer to and why two a day")
        #expect(scripted.asked == [
            AIConversation(question: "how do tides work"),
            AIConversation(earlier: [first], question: "and why two a day"),
            AIConversation(earlier: [first, second], question: "and the Sun?"),
        ])
        #expect(asking.question == "and the Sun?")
        #expect(asking.answer == "answer to and the Sun?")
        #expect(asking.state == .finished)
        #expect(asking.draft.isEmpty, "the field is ready for the next one")
        #expect(asking.leftOut == 0)
    }

    @Test func oneQuestionWithNoFollowUpSendsWhatItAlwaysSent() async throws {
        let scripted = ScriptedSource()
        let asking = AskAIModel(question: "why is the sky blue", source: source, request: scripted.request)
        await asking.ask().value
        let sent = try #require(scripted.asked.first)
        #expect(scripted.asked.count == 1)
        #expect(sent == AIConversation(question: "why is the sky blue"))
        // What each source makes of it is what it was before there were follow-ups.
        #expect(sent.replayedPrompt == "why is the sky blue", "a tool reads the question and nothing else")
        #expect(sent.earlierMessages.isEmpty, "an API is sent one user message")
        #expect(AppleIntelligence.transcript(of: sent).isEmpty, "Apple Intelligence starts a session with no transcript")
        #expect(asking.turns.isEmpty)
        #expect(asking.leftOut == 0)
    }

    @Test func theEarlierTurnsAreKeptAsTheyWereParsedAndInOrder() async throws {
        let scripted = ScriptedSource([.success("# One\n\nfirst"), .success("second, **bold**"), .success("third")])
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        await asking.ask().value
        let firstShown = asking.shown
        try await followUp(asking, "q2")
        let secondShown = asking.shown
        try await followUp(asking, "q3")

        #expect(asking.turns.map(\.id) == [0, 1])
        #expect(asking.turns.map(\.question) == ["q1", "q2"])
        #expect(asking.turns.map(\.answer) == ["# One\n\nfirst", "second, **bold**"])
        #expect(asking.turns.map(\.shown) == [firstShown, secondShown], "an earlier answer is not parsed again")
        #expect(asking.shown == MarkdownContent("third"))
    }

    @Test func onlyTheAnswerBeingStreamedIsParsed() async throws {
        let parsed = Mutex<[String]>([])
        let scripted = ScriptedSource([.success("first answer"), .success("second answer")], early: ["sec", "ond"])
        let asking = AskAIModel(
            question: "q1",
            source: source,
            request: scripted.request,
            parse: { text, shown in
                parsed.withLock { $0.append(text) }
                return await MarkdownContent.parsed(text, reusing: shown)
            },
            pause: { /* no time passes between two updates */ }
        )
        await asking.ask().value
        parsed.withLock { $0 = [] }
        try await followUp(asking, "q2")
        #expect(asking.shown.text == "second answer")
        #expect(!parsed.withLock { $0 }.contains { $0.contains("first") }, "the earlier answer is drawn from what was kept")
    }

    // MARK: The limit

    @Test func aLongConversationDropsItsOldestTurnsAndSaysSo() async throws {
        let scripted = ScriptedSource()
        let asking = AskAIModel(question: "q0", source: source, limit: AIConversation.Limit(turns: 2, characters: 12000), request: scripted.request)
        await asking.ask().value
        try await followUp(asking, "q1")
        try await followUp(asking, "q2")
        #expect(asking.leftOut == 0, "nothing is said while every turn is sent")
        try await followUp(asking, "q3")

        #expect(scripted.asked.last?.earlier.map(\.question) == ["q1", "q2"], "the oldest turn is the one left out")
        #expect(asking.leftOut == 1)
        #expect(asking.turns.map(\.question) == ["q0", "q1", "q2"], "it is still on screen")
        try await followUp(asking, "q4")
        #expect(scripted.asked.last?.earlier.map(\.question) == ["q2", "q3"])
        #expect(asking.leftOut == 2)
    }

    @Test func theLimitCountsTheTextToo() async throws {
        let long = String(repeating: "x", count: 40)
        let scripted = ScriptedSource([.success(long), .success("short"), .success("last")])
        let asking = AskAIModel(question: "q0", source: source, limit: AIConversation.Limit(turns: 8, characters: 30), request: scripted.request)
        await asking.ask().value
        try await followUp(asking, "q1")
        #expect(scripted.asked.last?.earlier.isEmpty == true, "an answer too long to send again is left out whole")
        #expect(asking.leftOut == 1)
        try await followUp(asking, "q2")
        #expect(scripted.asked.last?.earlier == [Turn(question: "q1", answer: "short")])
        #expect(asking.leftOut == 1)
    }

    @Test func theLauncherGivesAppleIntelligenceItsOwnLimit() {
        let model = makeLauncher(ScriptedSource())
        model.settings.aiSource = .appleIntelligence
        model.openAskAI("q")
        #expect(model.askAI?.limit == .appleIntelligence)
        model.settings.aiSource = .tools
        model.openAskAI("q")
        #expect(model.askAI?.limit == .standard)
        model.closeAskAI()
    }

    // MARK: Ask Again

    @Test func askAgainReplacesTheLastAnswerAndAddsNoTurn() async throws {
        let scripted = ScriptedSource([.success("a1"), .success("a2"), .success("a2 again"), .success("a3")])
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        await asking.ask().value
        try await followUp(asking, "q2")
        #expect(asking.answer == "a2")

        await asking.ask().value
        #expect(asking.answer == "a2 again")
        #expect(asking.shown.text == "a2 again")
        #expect(asking.question == "q2")
        #expect(asking.turns.map(\.question) == ["q1"], "the question asked again did not become a turn of its own")
        let earlier = [Turn(question: "q1", answer: "a1")]
        #expect(Array(scripted.asked.suffix(2)) == [
            AIConversation(earlier: earlier, question: "q2"),
            AIConversation(earlier: earlier, question: "q2"),
        ], "the same question went with the same earlier turns")

        try await followUp(asking, "q3")
        #expect(scripted.asked.last == AIConversation(earlier: earlier + [Turn(question: "q2", answer: "a2 again")], question: "q3"), "the answer that was replaced is not sent")
    }

    // MARK: Failing and stopping

    @Test func aFailedFollowUpKeepsTheEarlierTurnsAndItsQuestion() async throws {
        let scripted = ScriptedSource([.success("a1"), .failure(.failed("The model is not there.")), .success("a2")])
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        await asking.ask().value
        try await followUp(asking, "q2")

        #expect(asking.state == .failed("The model is not there."))
        #expect(asking.question == "q2", "the question is still there to try again")
        #expect(asking.turns.map(\.question) == ["q1"])
        #expect(asking.turns.map(\.answer) == ["a1"])
        #expect(asking.answer.isEmpty)
        #expect(asking.returnAction == .askAgain)

        asking.primaryAction()
        await waitFor("the answer to the second try") { asking.state == .finished }
        #expect(asking.answer == "a2")
        #expect(scripted.asked.last == AIConversation(earlier: [Turn(question: "q1", answer: "a1")], question: "q2"))
        #expect(asking.turns.map(\.question) == ["q1"])
    }

    @Test func aQuestionThatFailedIsNotSentWithTheNextOne() async throws {
        let scripted = ScriptedSource([.success("a1"), .failure(.failed("No.")), .success("a3")])
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        await asking.ask().value
        try await followUp(asking, "q2")
        try await followUp(asking, "q3")
        #expect(scripted.asked.last == AIConversation(earlier: [Turn(question: "q1", answer: "a1")], question: "q3"))
        #expect(asking.turns.map(\.question) == ["q1"], "a question with no answer is not kept as a turn")
        #expect(asking.state == .finished)
    }

    @Test func aFollowUpWhileAnAnswerStreamsStopsItAndKeepsNoneOfIt() async throws {
        let scripted = ScriptedSource([.success("a1"), .success("never"), .success("a3")], early: ["partial"], waits: true)
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        let first = asking.ask()
        await waitFor("the first text") { asking.answer == "partial" }
        scripted.open()
        await first.value
        #expect(asking.answer == "a1")

        asking.draft = "q2"
        asking.askFollowUp()
        await waitFor("the second answer's first text") { asking.answer == "partial" && scripted.asked.count == 2 }
        asking.draft = "q3"
        let third = try #require(asking.askFollowUp())
        #expect(asking.state == .asking)
        #expect(asking.answer.isEmpty, "the answer that was arriving is gone at once")
        await waitFor("the second request to be cancelled") { scripted.cancellations == 1 }
        await waitFor("the third request") { scripted.asked.count == 3 }
        scripted.open()
        await third.value

        #expect(asking.answer == "a3")
        #expect(asking.turns.map(\.question) == ["q1"], "the question that was interrupted is not a turn")
        #expect(scripted.asked.last == AIConversation(earlier: [Turn(question: "q1", answer: "a1")], question: "q3"))
    }

    // MARK: Leaving

    @Test func closingTheViewClearsTheConversation() async throws {
        let scripted = ScriptedSource()
        let model = makeLauncher(scripted)
        model.query = "ask how do tides work"
        model.openAskAI("how do tides work")
        let asking = try #require(model.askAI)
        await waitFor("the first answer") { asking.state == .finished }
        try await followUp(asking, "and why two a day")
        asking.draft = "half a thought"
        #expect(asking.turns.count == 1)

        #expect(try model.handleKey(key(53)), "Escape goes back whatever is in the field")
        #expect(model.askAI == nil)
        #expect(asking.turns.isEmpty)
        #expect(asking.answer.isEmpty)
        #expect(asking.shown == .empty)
        #expect(asking.draft.isEmpty)
        #expect(asking.leftOut == 0)
        #expect(asking.state == .cancelled)
        #expect(model.query == "ask how do tides work", "the search is as it was left")
    }

    @Test func hidingThePanelClearsTheConversation() async throws {
        let model = makeLauncher(ScriptedSource())
        model.openAskAI("q1")
        let asking = try #require(model.askAI)
        await waitFor("the first answer") { asking.state == .finished }
        try await followUp(asking, "q2")
        model.panelDidHide()
        #expect(model.askAI == nil)
        #expect(asking.turns.isEmpty)
        #expect(asking.answer.isEmpty)
    }

    @Test func aNewQuestionFromTheSearchStartsAFreshConversation() async throws {
        let scripted = ScriptedSource()
        let model = makeLauncher(scripted)
        model.openAskAI("q1")
        let first = try #require(model.askAI)
        await waitFor("the first answer") { first.state == .finished }
        try await followUp(first, "q2")

        model.openAskAI("something else")
        let second = try #require(model.askAI)
        #expect(second !== first)
        #expect(first.turns.isEmpty, "the conversation that was open is dropped")
        #expect(first.state == .cancelled)
        await waitFor("the new answer") { second.state == .finished }
        #expect(scripted.asked.last == AIConversation(question: "something else"), "nothing of the earlier conversation goes with it")
        #expect(second.turns.isEmpty)
        model.closeAskAI()
    }

    @Test func nothingOfAConversationIsStored() async throws {
        let scripted = ScriptedSource([.success("a secret answer"), .success("another secret answer")])
        let model = makeLauncher(scripted)
        model.openAskAI("a secret question")
        let asking = try #require(model.askAI)
        await waitFor("the first answer") { asking.state == .finished }
        try await followUp(asking, "a secret follow-up")
        model.settings.save()
        model.closeAskAI()
        model.settings.save()

        let stored = scratch.defaults.dictionaryRepresentation()
        #expect(stored.keys.contains("settings"), "the settings were saved, so there is something to look through")
        let text = stored.values.map { value in
            (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: value)
        }.joined()
        #expect(!text.contains("secret"), "no question, answer or follow-up is in what Floe saves")
    }

    // MARK: Keys

    @Test func returnCopiesWithAnEmptyFieldAndAsksOnceSomethingIsTyped() async {
        let scripted = ScriptedSource()
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        #expect(asking.returnAction == .nothing, "nothing has been asked yet")
        await asking.ask().value
        #expect(asking.returnAction == .copyAnswer, "as it was before follow-ups")
        asking.draft = "   "
        #expect(asking.returnAction == .copyAnswer, "spaces are not a question")
        #expect(asking.askFollowUp() == nil)
        #expect(scripted.asked.count == 1)
        asking.draft = "q2"
        #expect(asking.returnAction == .askFollowUp)
    }

    @Test func whileAnAnswerIsOnItsWayReturnDoesNothingUnlessSomethingIsTyped() async {
        let scripted = ScriptedSource([], early: ["par"], waits: true)
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        let task = asking.ask()
        #expect(asking.returnAction == .nothing)
        await waitFor("the first text") { asking.answer == "par" }
        #expect(asking.returnAction == .nothing)
        asking.draft = "q2"
        #expect(asking.returnAction == .askFollowUp)
        asking.draft = ""
        scripted.open()
        await task.value
        #expect(asking.returnAction == .copyAnswer)
    }

    @Test func returnInTheLauncherAsksTheFollowUpThatWasTyped() async throws {
        let scripted = ScriptedSource()
        let model = makeLauncher(scripted)
        model.openAskAI("q1")
        let asking = try #require(model.askAI)
        await waitFor("the first answer") { asking.state == .finished }
        asking.draft = "q2"
        #expect(try model.handleKey(key(36)))
        #expect(asking.question == "q2")
        #expect(asking.draft.isEmpty)
        await waitFor("the follow-up's answer") { asking.state == .finished }
        #expect(scripted.asked.last == AIConversation(earlier: [AIConversation.Turn(question: "q1", answer: "answer to q1")], question: "q2"))

        // Enter on the keypad is Return, and Command-R asks the follow-up again.
        asking.draft = "q3"
        #expect(try model.handleKey(key(76)))
        await waitFor("the third answer") { asking.state == .finished && asking.question == "q3" }
        #expect(try model.handleKey(key(15, .command)))
        await waitFor("the third question asked again") { scripted.asked.count == 4 && asking.state == .finished }
        #expect(scripted.asked.suffix(2).map(\.question) == ["q3", "q3"])
        #expect(asking.turns.map(\.question) == ["q1", "q2"])
        model.closeAskAI()
    }

    @Test func commandReturnPastesTheAnswerWhateverIsInTheField() async throws {
        let scripted = ScriptedSource()
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        var pasted: [String] = []
        asking.host = ModeHost(paste: { pasted.append($0) })
        await asking.ask().value
        #expect(try asking.handleKey(key(36, .command), .command))
        asking.draft = "q2"
        #expect(try asking.handleKey(key(36, .command), .command))
        #expect(pasted == ["answer to q1", "answer to q1"])
        #expect(scripted.asked.count == 1, "nothing was asked")
        #expect(asking.draft == "q2")
    }

    @Test func typingAndItsShortcutsAreLeftToTheFieldAndTheArrowsStillScroll() throws {
        let asking = AskAIModel(question: "q1", source: source, request: ScriptedSource().request)
        #expect(try !asking.handleKey(key(0), []), "a letter")
        #expect(try !asking.handleKey(key(49), []), "the space bar")
        #expect(try !asking.handleKey(key(51), []), "Delete")
        #expect(try !asking.handleKey(key(123), []), "the left arrow moves in the text")
        #expect(try !asking.handleKey(key(0, .command), .command), "Command-A selects the text")
        #expect(try !asking.handleKey(key(9, .command), .command), "Command-V pastes into it")
        #expect(try asking.handleKey(key(125), []))
        #expect(asking.scroll == AskAIModel.Scroll(id: 1, lines: 1))
        #expect(try asking.handleKey(key(126), []))
        #expect(asking.scroll == AskAIModel.Scroll(id: 2, lines: -1))
    }

    @Test func theFieldTakesTheKeyboardWhenAnAnswerEnds() async throws {
        let scripted = ScriptedSource([.success("a1"), .failure(.failed("No."))])
        let asking = AskAIModel(question: "q1", source: source, request: scripted.request)
        #expect(asking.focus == 0)
        await asking.ask().value
        #expect(asking.focus == 1, "a follow-up can be typed at once")
        try await followUp(asking, "q2")
        #expect(asking.focus == 2, "after a failure too, to ask something else")
    }
}
