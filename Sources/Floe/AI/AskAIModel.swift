//
//  AskAIModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A question, its answer and the turns before them, for as long as the answer view is on screen.
/// The conversation is kept in memory and never saved: leaving the view drops all of it.
final class AskAIModel: ObservableObject {
    /// Answers a question that may have earlier turns, handing over text as it arrives, and returns the whole answer.
    typealias Request = @concurrent @Sendable (AIConversation, @Sendable (String) async -> Void) async throws -> String
    /// Parses the answer so far, away from the main actor. It is handed what is shown, to keep the blocks that did not change.
    typealias Parse = @concurrent @Sendable (String, MarkdownContent) async -> MarkdownContent
    /// Waits out the time between two updates of an answer that is streaming.
    typealias Pause = @Sendable () async -> Void

    /// Twelve updates a second still read as text arriving, and a source sends several tokens in that time.
    static let batchInterval = Duration.milliseconds(80)

    enum State: Equatable {
        /// Sent, and nothing has come back yet.
        case asking
        /// Text is arriving.
        case answering
        case finished
        /// The source's own words for why there is no answer.
        case failed(String)
        /// The view was left before the answer was complete, or after it.
        case cancelled
    }

    /// A request to scroll the answer, made by the arrow keys. `id` tells two equal steps apart.
    struct Scroll: Equatable {
        var id = 0
        var lines = 0
    }

    /// A question that was answered before the one on screen. It keeps the answer as it was parsed.
    struct Turn: Identifiable, Equatable {
        let id: Int
        let question: String
        let answer: String
        let shown: MarkdownContent
    }

    /// The question being answered: the first one, then each follow-up in its turn.
    @Published private(set) var question: String
    let source: AskAI.Source?
    /// How much of the earlier turns goes with a question.
    let limit: AIConversation.Limit
    @Published private(set) var state = State.asking
    /// Everything received so far, for copy and paste. Not published: the view draws `shown`.
    private(set) var answer = ""
    /// The answer as it is drawn: parsed, and at most one batch behind `answer` while it streams.
    @Published private(set) var shown = MarkdownContent.empty
    @Published private(set) var scroll = Scroll()
    /// The turns answered before this question, oldest first.
    @Published private(set) var turns: [Turn] = []
    /// What is typed in the field: the next question.
    @Published var draft = ""
    /// How many of the oldest turns the last request left out, because the rest filled the limit.
    @Published private(set) var leftOut = 0
    /// Bumped when an answer ends, so the field has the keyboard for a follow-up.
    @Published private(set) var focus = 0

    /// How the answer view reaches the panel. The launcher model fills it in when it shows the view.
    var host = ModeHost()

    private let request: Request
    private let parse: Parse
    private let pause: Pause
    private var task: Task<Void, Never>?
    /// Draws the text of a streaming answer in batches; nil when everything received is shown.
    /// Readable so a test can wait for it.
    private(set) var showing: Task<Void, Never>?
    /// Counts the parses started, so the result of an older one is dropped when it lands late.
    private var revision = 0
    /// Bumped per request, so text from one that was replaced or left is dropped.
    private var generation = 0

    /// How Ask AI is answered: by the source chosen on the AI page, as an extension's `AI.ask` is.
    static let live: Request = { conversation, emit in
        let (choice, localOnly) = await MainActor.run { (AIAnswer.configured(), AppSettings.shared.aiOnThisMacOnly) }
        return try await AIAnswer.answer(conversation, model: nil, choice: choice, localOnly: localOnly, emit: emit)
    }

    init(
        question: String,
        source: AskAI.Source?,
        limit: AIConversation.Limit = .standard,
        request: @escaping Request = AskAIModel.live,
        parse: @escaping Parse = { await MarkdownContent.parsed($0, reusing: $1) },
        pause: @escaping Pause = { try? await Task.sleep(for: AskAIModel.batchInterval) }
    ) {
        self.question = question
        self.source = source
        self.limit = limit
        self.request = request
        self.parse = parse
        self.pause = pause
    }

    var isWorking: Bool {
        state == .asking || state == .answering
    }

    /// Whether there is a follow-up to send: Return asks it, and otherwise acts on the answer.
    var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sends the question with the earlier turns that fit, replacing any request still in flight and
    /// the answer on screen. The task is returned so a test can wait for it.
    @discardableResult
    func ask() -> Task<Void, Never> {
        task?.cancel()
        generation += 1
        let started = generation
        clear()
        state = .asking
        let request = request
        let fitted = AIConversation.fitting(turns.map { AIConversation.Turn(question: $0.question, answer: $0.answer) }, limit: limit)
        if leftOut != fitted.dropped {
            leftOut = fitted.dropped
        }
        // Only the turns go along: the prompt, the messages or the transcript is made off the main actor, with the request.
        let conversation = AIConversation(earlier: fitted.kept, question: question)
        let emit: @Sendable (String) async -> Void = { [weak self] text in
            await MainActor.run { [weak self] in self?.receive(text, generation: started) }
        }
        let task = Task { @MainActor [weak self] in
            let result: Result<String, Error>
            do {
                result = try await .success(request(conversation, emit))
            } catch {
                result = .failure(error)
            }
            await self?.finish(result, generation: started)
        }
        self.task = task
        return task
    }

    /// Asks what is in the field. An answered question joins the earlier turns; one that failed or was
    /// still being answered has nothing to keep, and is replaced. Nil when the field is empty.
    @discardableResult
    func askFollowUp() -> Task<Void, Never>? {
        let next = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return nil }
        if state == .finished, !answer.isEmpty {
            turns.append(Turn(id: turns.count, question: question, answer: answer, shown: shown))
        }
        question = next
        draft = ""
        return ask()
    }

    /// Stops the request and forgets the conversation. Called when the view is left or the panel hides.
    func leave() {
        generation += 1
        task?.cancel()
        task = nil
        clear()
        turns = []
        draft = ""
        leftOut = 0
        state = .cancelled
    }

    /// Forgets the answer on screen and stops drawing it. A parse still running is for an older generation, and is dropped.
    private func clear() {
        showing?.cancel()
        showing = nil
        answer = ""
        shown = .empty
    }

    func scroll(by lines: Int) {
        scroll = Scroll(id: scroll.id + 1, lines: lines)
    }

    private func receive(_ text: String, generation started: Int) {
        guard started == generation else { return }
        answer += text
        // Published once, not per token: every change here evaluates the view again.
        if state != .answering {
            state = .answering
        }
        show(generation: started)
    }

    /// Draws what has arrived and then waits, for as long as text keeps arriving: one parse per interval,
    /// however many tokens came in it. The first text is drawn at once.
    private func show(generation started: Int) {
        guard showing == nil else { return }
        showing = Task { @MainActor [weak self, parse, pause] in
            while !Task.isCancelled, let next = self?.nextToShow(generation: started) {
                let content = await parse(next.text, next.shown)
                guard self?.apply(content, revision: next.revision, generation: started) == true else { return }
                await pause()
            }
        }
    }

    /// The text to parse next, or nil when all of it is shown, which ends the batch loop.
    private func nextToShow(generation started: Int) -> (text: String, shown: MarkdownContent, revision: Int)? {
        guard started == generation else { return nil }
        guard answer != shown.text else {
            showing = nil
            return nil
        }
        revision += 1
        return (answer, shown, revision)
    }

    /// False when the parse is stale: the request was replaced or left, or a newer parse has started since.
    private func apply(_ content: MarkdownContent, revision parsed: Int, generation started: Int) -> Bool {
        guard started == generation, parsed == revision else { return false }
        shown = content
        return true
    }

    private func finish(_ result: Result<String, Error>, generation started: Int) async {
        guard started == generation else { return }
        // A source that does not stream hands over everything here.
        if case let .success(whole) = result, !whole.isEmpty {
            answer = whole
        }
        showing?.cancel()
        showing = nil
        // The whole text is drawn before the state changes, so nothing reads as finished over part of an answer.
        if answer != shown.text {
            revision += 1
            let content = await parse(answer, shown)
            guard started == generation else { return }
            shown = content
        }
        task = nil
        switch result {
        case .success:
            state = .finished
        case let .failure(error):
            state = .failed(error.localizedDescription)
        }
        focus += 1
    }

    deinit {
        task?.cancel()
        showing?.cancel()
    }
}
