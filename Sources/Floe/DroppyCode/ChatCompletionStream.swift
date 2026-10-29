//
//  ChatCompletionStream.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/Providers/OpenAICompatibleSession.swift, and modified:
//  only the streamed request is kept (the request, the error body, the SSE lines, the retry of a
//  dropped connection), for one prompt and one answer. The agent around it is left out: tools,
//  history, approvals, reasoning and token counts. Text is batched in the read loop, not by an
//  actor, and a reply that already showed text is not restarted, since an extension has no way
//  to take text back. The request can carry the turns before its prompt, for Ask AI's follow-up
//  questions; they are the caller's to keep, and nothing is stored here. A redirect is never
//  followed, so the question and the key go only to the address that was checked.

import Foundation

nonisolated enum ProviderError: LocalizedError, Equatable {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

/// One prompt, streamed back from an OpenAI-compatible chat completions endpoint.
nonisolated enum ChatCompletionStream {
    /// A lost connection is retried twice: once after a second, once after two more.
    /// Nothing else (a rejected key, a validation error, a stop) is retried.
    static let transportRetryDelays: [Duration] = [.seconds(1), .seconds(2)]

    /// Text is handed on at most this often, so a fast stream costs fewer hops.
    private static let batchInterval: Duration = .milliseconds(30)

    /// The transport failures worth another attempt, by code rather than by message:
    /// the connection went away, the request timed out, or the host was unreachable.
    static func isTransientTransportFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost: return true
        default: return false
        }
    }

    /// What one line of the stream says.
    enum Event: Equatable {
        case text(String)
        case failure(String)
        case done
    }

    /// Nil for a line that carries nothing to show: a comment, a keep-alive, a role or usage chunk.
    static func event(in line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let data = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if data == "[DONE]" {
            return .done
        }
        guard let json = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any] else { return nil }
        if let error = json["error"], !(error is NSNull) {
            return .failure((error as? [String: Any])?["message"] as? String ?? String(describing: error))
        }
        guard let choice = (json["choices"] as? [[String: Any]])?.first,
              let text = (choice["delta"] as? [String: Any])?["content"] as? String,
              !text.isEmpty
        else { return nil }
        return .text(text)
    }

    /// `earlier` is the messages of the turns before the prompt, oldest first; a first question has none.
    static func request(chatURL: URL, apiKey: String, model: String, prompt: String, earlier: [[String: String]] = []) -> URLRequest {
        var request = URLRequest(url: chatURL, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // A server on the same Mac takes no key, and an empty one would be a malformed header.
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload: [String: Any] = [
            "model": model,
            "messages": earlier + [["role": "user", "content": prompt]],
            "stream": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// The API's own words for a refused request, or its status when it sent none.
    static func errorMessage(fromBody body: String, statusCode: Int) -> String {
        if let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? json["message"] as? String
            if let message, !message.isEmpty {
                return message
            }
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(500))
        }
        return String(localized: "The API returned status \(statusCode).", bundle: .floe, comment: "The placeholder is an HTTP status number such as 500.")
    }

    static let redirectRefusedMessage = String(
        localized: "The API sent the request on to another address. Floe doesn't follow it, so nothing was sent there. Check the address under Settings › AI.",
        bundle: .floe
    )

    /// Refuses every redirect. The address was checked before the request (HTTPS, or a server on this Mac, and the
    /// key bound to it), and a redirect, a 307 or 308 above all, would carry the question and the key past that check.
    private final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest _: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    /// What is left when the connection keeps dropping: how many times the same
    /// request was tried, and the transport's own reason, so the user can act on it.
    static func terminalTransportMessage(_ error: Error, attempts: Int) -> String {
        let reason = error.localizedDescription
        guard !reason.isEmpty else {
            return String(
                localized: "The API could not be reached after \(attempts) attempts. Check the connection, then try again.",
                bundle: .floe,
                comment: "The placeholder is how many times the request was tried."
            )
        }
        return String(
            localized: "The API could not be reached after \(attempts) attempts. Check the connection, then try again. (\(reason))",
            bundle: .floe,
            comment: "The first placeholder is how many times the request was tried and the second is the system's own reason for the failure."
        )
    }

    /// Sends the request and returns the whole answer, handing each batch of text to `onText` as
    /// it arrives. `session` and `retryDelays` are parameters so a test can stand in for the network.
    @concurrent
    static func run(
        _ request: URLRequest,
        session: URLSession = .shared,
        retryDelays: [Duration] = transportRetryDelays,
        onText: @Sendable (String) async -> Void
    ) async throws -> String {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            var answer = ""
            do {
                try await stream(request, session: session, into: &answer, onText: onText)
                guard !answer.isEmpty else {
                    throw ProviderError.failed(String(localized: "The model gave no answer.", bundle: .floe))
                }
                return answer
            } catch {
                try Task.checkCancellation()
                // Anything that is not a dropped connection keeps the error it came with.
                guard isTransientTransportFailure(error) else { throw error }
                guard answer.isEmpty, attempt < retryDelays.count else {
                    throw ProviderError.failed(terminalTransportMessage(error, attempts: attempt + 1))
                }
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            }
        }
    }

    /// Throws for any status but 200: a redirect that was not followed, or a refusal in the API's own words.
    private static func refuseUnlessAnswered(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        if (300 ..< 400).contains(http.statusCode) {
            throw ProviderError.failed(redirectRefusedMessage)
        }
        // Read the error body for a useful message.
        var body = ""
        for try await line in bytes.lines {
            body += line + "\n"
            if body.count > 8000 {
                break
            }
        }
        throw ProviderError.failed(errorMessage(fromBody: body, statusCode: http.statusCode))
    }

    private static func stream(
        _ request: URLRequest,
        session: URLSession,
        into answer: inout String,
        onText: @Sendable (String) async -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefusal())
        try await refuseUnlessAnswered(response, bytes: bytes)
        let clock = ContinuousClock()
        var pending = ""
        // The first piece goes out at once; later ones wait for the interval.
        var lastBatch = clock.now - batchInterval
        lines: for try await line in bytes.lines {
            switch event(in: line) {
            case let .text(text):
                answer += text
                pending += text
                if clock.now - lastBatch >= batchInterval {
                    await onText(pending)
                    pending = ""
                    lastBatch = clock.now
                }
            case let .failure(message):
                throw ProviderError.failed(message)
            case .done:
                break lines
            case nil:
                continue
            }
        }
        if !pending.isEmpty {
            await onText(pending)
        }
    }
}
