//
//  ChatCompletionStreamTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import os
import Testing

/// Answers requests in place of the network. Each test registers its own replies under a path of
/// its own, because tests run in parallel and a URLProtocol class is shared.
private final nonisolated class StubProtocol: URLProtocol {
    enum Reply {
        case response(status: Int, body: String)
        case failure(URLError.Code)
        /// Sends the request on to `location`, keeping its method and body as a 307 or 308 does.
        case redirect(status: Int, location: URL)
    }

    private static let replies = OSAllocatedUnfairLock(initialState: [String: [Reply]]())
    private static let requests = OSAllocatedUnfairLock(initialState: [String: Int]())

    static func queue(_ replies: [Reply], for path: String) {
        Self.replies.withLock { $0[path] = replies }
    }

    static func requestCount(for path: String) -> Int {
        requests.withLock { $0[path] ?? 0 }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.requests.withLock { $0[path, default: 0] += 1 }
        let reply = Self.replies.withLock { replies -> Reply? in
            guard var queued = replies[path], !queued.isEmpty else { return nil }
            let next = queued.removeFirst()
            replies[path] = queued
            return next
        }
        switch reply {
        case let .response(status, body):
            if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .redirect(status, location):
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": location.absoluteString])
            else { return }
            var next = request
            next.url = location
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }
    }

    override func stopLoading() {
        // Nothing is in flight: every reply is delivered at once.
    }
}

/// Collects what `onText` is handed.
private actor Pieces {
    private(set) var all: [String] = []
    func add(_ piece: String) {
        all.append(piece)
    }
}

struct ChatCompletionStreamTests {
    private let path = "/\(UUID().uuidString)/chat/completions"
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }()

    private var request: URLRequest {
        ChatCompletionStream.request(chatURL: URL(string: "https://api.test\(path)") ?? URL(fileURLWithPath: "/"), apiKey: "key-123", model: "small", prompt: "why?")
    }

    private func chunk(_ text: String) -> String {
        "data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\n\n"
    }

    private func run(_ replies: [StubProtocol.Reply], pieces: Pieces = Pieces()) async throws -> String {
        StubProtocol.queue(replies, for: path)
        return try await ChatCompletionStream.run(request, session: session, retryDelays: [.milliseconds(1), .milliseconds(1)]) { await pieces.add($0) }
    }

    // MARK: The request

    @Test func theRequestAsksForAStreamOfOnePromptWithTheKey() throws {
        let request = request
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "small")
        #expect(body["stream"] as? Bool == true)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "why?"]])
    }

    // MARK: Lines

    @Test func aContentDeltaIsText() {
        #expect(ChatCompletionStream.event(in: #"data: {"choices":[{"delta":{"content":"be"}}]}"#) == .text("be"))
        #expect(ChatCompletionStream.event(in: #"  data:{"choices":[{"delta":{"content":"cause"}}]}  "#) == .text("cause"))
    }

    @Test func theEndMarkerEndsTheStream() {
        #expect(ChatCompletionStream.event(in: "data: [DONE]") == .done)
    }

    @Test func anErrorObjectIsAFailureInTheAPIsWords() {
        #expect(ChatCompletionStream.event(in: #"data: {"error":{"message":"quota exceeded"}}"#) == .failure("quota exceeded"))
        #expect(ChatCompletionStream.event(in: #"data: {"error":"overloaded"}"#) == .failure("overloaded"))
    }

    @Test(arguments: [
        ": keep-alive",
        "event: ping",
        "data: not json",
        #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
        #"data: {"choices":[{"delta":{"content":""}}]}"#,
        #"data: {"choices":[],"usage":{"total_tokens":12}}"#,
        #"data: {"error":null,"choices":[]}"#,
    ])
    func linesWithNothingToShowAreSkipped(line: String) {
        #expect(ChatCompletionStream.event(in: line) == nil)
    }

    // MARK: Errors

    @Test func aRefusedRequestIsReportedInTheAPIsWords() {
        #expect(ChatCompletionStream.errorMessage(fromBody: #"{"error":{"message":"Incorrect API key"}}"#, statusCode: 401) == "Incorrect API key")
        #expect(ChatCompletionStream.errorMessage(fromBody: #"{"message":"no such model"}"#, statusCode: 404) == "no such model")
        #expect(ChatCompletionStream.errorMessage(fromBody: " gateway timeout \n", statusCode: 504) == "gateway timeout")
        #expect(ChatCompletionStream.errorMessage(fromBody: "", statusCode: 502) == "The API returned status 502.")
        #expect(ProviderError.failed("gone").errorDescription == "gone")
    }

    @Test func onlyADroppedConnectionIsWorthAnotherAttempt() {
        for code in [URLError.Code.networkConnectionLost, .timedOut, .cannotConnectToHost] {
            #expect(ChatCompletionStream.isTransientTransportFailure(URLError(code)))
        }
        #expect(!ChatCompletionStream.isTransientTransportFailure(URLError(.userAuthenticationRequired)))
        #expect(!ChatCompletionStream.isTransientTransportFailure(ProviderError.failed("no")))
        #expect(ChatCompletionStream.terminalTransportMessage(URLError(.timedOut), attempts: 3).contains("after 3 attempts"))
    }

    // MARK: Running

    @Test func theAnswerIsEveryPieceInOrder() async throws {
        let pieces = Pieces()
        let body = chunk("be") + ": keep-alive\n\n" + chunk("cause") + "data: [DONE]\n\n" + chunk("ignored")
        #expect(try await run([.response(status: 200, body: body)], pieces: pieces) == "because")
        #expect(await pieces.all.joined() == "because")
    }

    @Test func theStreamIsReadOffTheMainThread() async throws {
        let threads = ThreadLog()
        StubProtocol.queue([.response(status: 200, body: chunk("be") + "data: [DONE]\n\n")], for: path)
        let answer = try await ChatCompletionStream.run(request, session: session, retryDelays: []) { _ in threads.note("text") }
        #expect(answer == "be")
        #expect(threads.onMain == ["text": false])
    }

    @Test func aStreamWithoutAnEndMarkerStillAnswers() async throws {
        #expect(try await run([.response(status: 200, body: chunk("done"))]) == "done")
    }

    @Test func aRefusalThrowsWhatTheAPISaid() async {
        let error = await #expect(throws: ProviderError.self) {
            try await run([.response(status: 401, body: #"{"error":{"message":"Incorrect API key"}}"#)])
        }
        #expect(error == .failed("Incorrect API key"))
        #expect(StubProtocol.requestCount(for: path) == 1)
    }

    @Test func anErrorInsideTheStreamThrows() async {
        let error = await #expect(throws: ProviderError.self) {
            try await run([.response(status: 200, body: "data: {\"error\":{\"message\":\"overloaded\"}}\n\n")])
        }
        #expect(error == .failed("overloaded"))
    }

    @Test func anEmptyAnswerIsAnError() async {
        let error = await #expect(throws: ProviderError.self) {
            try await run([.response(status: 200, body: "data: [DONE]\n\n")])
        }
        #expect(error == .failed("The model gave no answer."))
    }

    @Test func aDroppedConnectionIsTriedAgain() async throws {
        let answer = try await run([.failure(.networkConnectionLost), .failure(.timedOut), .response(status: 200, body: chunk("third time"))])
        #expect(answer == "third time")
        #expect(StubProtocol.requestCount(for: path) == 3)
    }

    @Test func aConnectionThatKeepsDroppingGivesUpAndSaysSo() async {
        let error = await #expect(throws: ProviderError.self) {
            try await run([.failure(.timedOut), .failure(.timedOut), .failure(.timedOut), .response(status: 200, body: chunk("never"))])
        }
        #expect(error?.errorDescription?.contains("after 3 attempts") == true)
        #expect(StubProtocol.requestCount(for: path) == 3)
    }

    @Test(arguments: [301, 302, 307, 308])
    func aRedirectIsNotFollowedSoTheQuestionAndKeyStayWithTheAddressChosen(status: Int) async {
        let elsewhere = "/\(UUID().uuidString)/elsewhere"
        StubProtocol.queue([.response(status: 200, body: chunk("leaked"))], for: elsewhere)
        let error = await #expect(throws: ProviderError.self) {
            try await run([.redirect(status: status, location: URL(string: "https://elsewhere.test\(elsewhere)") ?? URL(fileURLWithPath: "/"))])
        }
        #expect(error == .failed(ChatCompletionStream.redirectRefusedMessage))
        #expect(StubProtocol.requestCount(for: elsewhere) == 0)
    }

    @Test func anyOtherTransportFailureIsNotRetried() async {
        await #expect(throws: URLError.self) {
            try await run([.failure(.userAuthenticationRequired), .response(status: 200, body: chunk("never"))])
        }
        #expect(StubProtocol.requestCount(for: path) == 1)
    }
}
