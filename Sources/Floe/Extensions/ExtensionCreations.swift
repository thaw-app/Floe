//
//  ExtensionCreations.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `Action.CreateSnippet` and `Action.CreateQuicklink`: what the user confirmed in the extension's form becomes a
/// snippet or a quicklink, kept by the same rules as one made in Settings.
enum ExtensionCreations {
    struct Refusal: LocalizedError {
        let errorDescription: String?
    }

    static func snippet(_ params: [String: Any], in store: SnippetStore) throws {
        let snippet = Snippet(
            name: text(params["name"]),
            keyword: text(params["keyword"]),
            text: params["text"] as? String ?? ""
        )
        if snippet.name.isEmpty {
            throw Refusal(errorDescription: String(localized: "Enter a name.", bundle: .floe))
        }
        if snippet.text.isEmpty {
            throw Refusal(errorDescription: String(localized: "Enter the snippet's text.", bundle: .floe))
        }
        if let problem = Snippet.keywordProblem(snippet.keyword, id: snippet.id, among: store.snippets) {
            throw Refusal(errorDescription: problem)
        }
        store.upsert(snippet)
    }

    static func quicklink(_ params: [String: Any], in store: QuicklinkStore) throws {
        let link = Quicklink(name: text(params["name"]), keyword: text(params["keyword"]), url: url(text(params["link"])))
        if let problem = store.problem(with: link) {
            throw Refusal(errorDescription: problem)
        }
        store.add(link)
    }

    /// Raycast's link takes what is typed after it as `{argument}`, named or not; Floe's takes it as `{query}`.
    static func url(_ link: String) -> String {
        link.replacing(#/\{argument[^}]*\}/#, with: "{query}")
    }

    private static func text(_ value: Any?) -> String {
        (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ExtensionSession {
    /// Answers `snippet.create` and `quicklink.create` once the item is kept, or with why it could not be.
    func answerCreation(id: Int, method: String, params: [String: Any]) {
        var reply: [String: Any] = ["type": "reply", "id": id]
        do {
            if method == "snippet.create" {
                try ExtensionCreations.snippet(params, in: .shared)
            } else {
                try ExtensionCreations.quicklink(params, in: .shared)
            }
            reply["result"] = NSNull()
        } catch {
            reply["error"] = error.localizedDescription
        }
        send(reply)
    }
}
