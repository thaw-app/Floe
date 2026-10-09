//
//  Keywords.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One word the search answers to, as `keywords` lists it: an example to adapt and what it does.
nonisolated struct KeywordHint: Hashable, Sendable {
    /// What has to be on, or there, for the word to do anything.
    enum Need: Hashable, Sendable {
        case nothing, shell, sshHosts, shortcuts, ownClipboard, ai
        /// A search source with its switch on, by the source's id.
        case source(String)
        /// A notes app that answers to the word.
        case notes
    }

    var keyword: String
    var example: String
    var detail: String
    var need = Need.nothing
    /// Whether text follows the word after a space. Emoji are named straight after the colon.
    var takesASpace = true

    /// What Return puts into the search field, to go on typing from.
    var typed: String {
        takesASpace ? keyword + " " : keyword
    }
}

/// The table, and what of it is offered. Apart from the value, since both read what belongs to the main actor.
extension KeywordHint {
    /// Every keyword, in the order the list shows them. The shell's row stands under the default prefix until `offered` reads the chosen one.
    static let all: [KeywordHint] = [
        KeywordHint(keyword: CommandPrefix.greaterThan.rawValue, example: "> brew update", detail: String(localized: "Run a shell command", bundle: .floe), need: .shell),
        KeywordHint(keyword: ReminderDraft.keyword, example: "remind call mom tomorrow at 5pm", detail: String(localized: "Add a reminder", bundle: .floe)),
        KeywordHint(keyword: EventDraft.keyword, example: "event lunch with Ana Thursday noon", detail: String(localized: "Add a calendar event", bundle: .floe)),
        KeywordHint(keyword: TimerDraft.keyword, example: "timer 10 minutes tea", detail: String(localized: "Start a countdown", bundle: .floe)),
        KeywordHint(keyword: "timers", example: "timers", detail: String(localized: "List the timers that are running", bundle: .floe)),
        KeywordHint(keyword: FocusRequest.keyword, example: "focus 1 hour", detail: String(localized: "Turn a Focus on for a while", bundle: .floe, comment: "Focus is the macOS feature that silences notifications.")),
        KeywordHint(keyword: NoteAction.new.keyword, example: "note buy milk", detail: String(localized: "Make a note", bundle: .floe), need: .notes),
        KeywordHint(keyword: NoteAction.append.keyword, example: "append call the bank", detail: String(localized: "Add a line to a note", bundle: .floe), need: .notes),
        KeywordHint(keyword: NoteAction.task.keyword, example: "todo renew passport", detail: String(localized: "Add a task to today’s note", bundle: .floe), need: .notes),
        KeywordHint(keyword: NoteAction.log.keyword, example: "log shipped the build", detail: String(localized: "Add a line with the time to today’s note", bundle: .floe), need: .notes),
        KeywordHint(keyword: OutgoingDraft.Kind.mail.keyword, example: "mail toni@example.com the build is ready", detail: String(localized: "Open an email draft", bundle: .floe)),
        KeywordHint(keyword: OutgoingDraft.Kind.message.keyword, example: "message +15551234567 running late", detail: String(localized: "Open a message draft", bundle: .floe)),
        KeywordHint(keyword: "contact", example: "contact ana", detail: String(localized: "Find a person in Contacts", bundle: .floe, comment: "Contacts is the name of Apple's app.")),
        KeywordHint(keyword: Checkpoint.keyword, example: "pause website redesign: fix the nav next", detail: String(localized: "Save a checkpoint of your files and tabs", bundle: .floe)),
        KeywordHint(keyword: "receipts", example: "receipts", detail: String(localized: "See what Floe did, and undo it", bundle: .floe)),
        KeywordHint(keyword: "files", example: "files invoice", detail: String(localized: "Find files by name", bundle: .floe), need: .source(SearchSourceInfo.files.id)),
        KeywordHint(keyword: "clipboard", example: "clipboard meeting", detail: String(localized: "Search what you copied", bundle: .floe), need: .ownClipboard),
        KeywordHint(keyword: "menu", example: "menu wifi", detail: String(localized: "Click a menu bar item", bundle: .floe)),
        KeywordHint(keyword: "tabs", example: "tabs invoice", detail: String(localized: "Switch to an open browser tab", bundle: .floe), need: .source(SearchSourceInfo.tabs.id)),
        KeywordHint(keyword: "ssh", example: "ssh web", detail: String(localized: "Connect to an SSH host", bundle: .floe), need: .sshHosts),
        KeywordHint(keyword: "shortcuts", example: "shortcuts mail", detail: String(localized: "Run one of your Shortcuts", bundle: .floe, comment: "Shortcuts are what the user makes in Apple's Shortcuts app."), need: .shortcuts),
        KeywordHint(keyword: Processes.keyword, example: "kill safari", detail: String(localized: "Quit a running process", bundle: .floe)),
        KeywordHint(keyword: Processes.portKeyword, example: "port 3000", detail: String(localized: "See what is listening on a port", bundle: .floe)),
        KeywordHint(keyword: AskAI.keyword, example: "ask how do tides work", detail: String(localized: "Ask AI a question", bundle: .floe), need: .ai),
        KeywordHint(keyword: EmojiSearchProvider.prefix, example: ":smile", detail: String(localized: "Find an emoji or a symbol", bundle: .floe), takesASpace: false),
    ]

    /// Whether the word does anything as things stand: its switch on, its source there.
    func isOffered(in context: SearchContext) -> Bool {
        switch need {
        case .nothing: true
        case .shell: context.shell.runs
        case .sshHosts: !context.sshHosts.isEmpty
        case .shortcuts: !context.shortcuts.isEmpty
        case .ownClipboard: context.clipboardDestination == .floe
        case .ai: context.canAskAI
        case let .source(id): context.searchSources.contains(id)
        case .notes: context.notesApp.actions.contains { $0.keyword == keyword }
        }
    }

    /// The keywords that work now. The shell's row is written with the prefix the user chose.
    static func offered(in context: SearchContext) -> [KeywordHint] {
        all.filter { $0.isOffered(in: context) }.map { hint in
            guard hint.need == .shell else { return hint }
            let prefix = context.shell.prefix.rawValue
            return KeywordHint(keyword: prefix, example: prefix + hint.example.dropFirst(hint.keyword.count), detail: hint.detail, need: .shell)
        }
    }

    /// The hints that hold every word typed, in the keyword, the example or what it does.
    static func matching(_ text: String, in hints: [KeywordHint]) -> [KeywordHint] {
        let words = text.lowercased().split(separator: " ")
        return hints.filter { hint in
            let haystack = "\(hint.keyword) \(hint.example) \(hint.detail)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

/// `keywords`, or a question mark: every word the search answers to, and with some text the ones that mention it.
struct KeywordSearchScope: SearchScope {
    static let word = "keywords"
    static let mark = "?"

    var keyword = KeywordSearchScope.word
    let title = String(localized: "Keywords", bundle: .floe, comment: "A section title. Keywords are the words the search answers to, such as remind or timer.")
    let emptyTitle = String(localized: "No keyword matches", bundle: .floe)

    /// The word alone lists everything, as `receipts` does.
    func text(in context: SearchContext) -> String? {
        if let text = context.text(after: keyword) {
            return text
        }
        return context.trimmed.lowercased() == keyword ? "" : nil
    }

    func results(for text: String, context: SearchContext) -> [RootItem] {
        KeywordHint.matching(text, in: KeywordHint.offered(in: context)).map(RootItem.keyword)
    }
}
