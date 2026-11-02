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
        KeywordHint(keyword: OpenWindows.keyword, example: "windows invoice", detail: String(localized: "Switch to an open window", bundle: .floe)),
        KeywordHint(keyword: MenuItems.keyword, example: "menus export", detail: String(localized: "Choose a command from the menus of the app in front", bundle: .floe)),
        KeywordHint(keyword: Bookmarks.keyword, example: "bookmarks invoice", detail: String(localized: "Open a bookmark of Chrome, Brave, Edge, Arc, Vivaldi, Dia or Helium", bundle: .floe, comment: "The names are browsers.")),
        KeywordHint(keyword: Homebrew.keyword, example: "brew ripgrep", detail: String(localized: "Install or upgrade a Homebrew package in your terminal", bundle: .floe, comment: "Homebrew is the name of a package manager.")),
        KeywordHint(keyword: RecentDocuments.keyword, example: "recent preview", detail: String(localized: "List the recently used files an application opens", bundle: .floe)),
        KeywordHint(keyword: "ssh", example: "ssh web", detail: String(localized: "Connect to an SSH host", bundle: .floe), need: .sshHosts),
        KeywordHint(keyword: "shortcuts", example: "shortcuts mail", detail: String(localized: "Run one of your Shortcuts", bundle: .floe, comment: "Shortcuts are what the user makes in Apple's Shortcuts app."), need: .shortcuts),
        KeywordHint(keyword: Processes.keyword, example: "kill safari", detail: String(localized: "Quit a running process", bundle: .floe)),
        KeywordHint(keyword: Processes.portKeyword, example: "port 3000", detail: String(localized: "See what is listening on a port", bundle: .floe)),
        KeywordHint(keyword: WordDefinition.keyword, example: "define tide", detail: String(localized: "Look a word up in the dictionary", bundle: .floe)),
        KeywordHint(keyword: WorldTime.keyword, example: "time in tokyo", detail: String(localized: "See the time in another city", bundle: .floe)),
        KeywordHint(keyword: SoundDevices.keyword(for: .output), example: "output airpods", detail: String(localized: "Choose the device sound plays through", bundle: .floe)),
        KeywordHint(keyword: SoundDevices.keyword(for: .input), example: "input macbook", detail: String(localized: "Choose the microphone", bundle: .floe)),
        KeywordHint(keyword: ScreenTools.qrKeyword, example: "qr https://example.com", detail: String(localized: "Make a QR code to copy or save", bundle: .floe)),
        KeywordHint(keyword: Places.keyword, example: "maps coffee in lisbon", detail: String(localized: "Find a place with Apple Maps. What you type is sent to Apple", bundle: .floe, comment: "Apple Maps is the name of Apple's service.")),
        KeywordHint(keyword: Translate.keyword, example: "translate hola mundo", detail: String(localized: "Translate a text with Apple's translation, on this Mac. Also translate to german good morning", bundle: .floe, comment: "The words after Also are typed as they are and stay in English.")),
        KeywordHint(keyword: SystemFacts.battery.rawValue, example: "battery", detail: String(localized: "See the battery's charge. Also disk, memory and ip", bundle: .floe, comment: "The last three words are typed as they are and stay in English.")),
        KeywordHint(keyword: Generators.uuidKeyword, example: "uuid", detail: String(localized: "Make a new UUID", bundle: .floe, comment: "A UUID is a random identifier programmers use.")),
        KeywordHint(keyword: Generators.passwordKeyword, example: "password 24", detail: String(localized: "Make a random password", bundle: .floe)),
        KeywordHint(keyword: Generators.loremKeyword, example: "lorem 2", detail: String(localized: "Make paragraphs of placeholder text", bundle: .floe)),
        KeywordHint(keyword: TextChange.base64.rawValue, example: "base64 hello", detail: String(localized: "Encode or change the case of a text. Also unbase64, urlencode, urldecode, uppercase, lowercase, titlecase, sha256", bundle: .floe, comment: "The words after Also are typed as they are and stay in English.")),
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

    /// The keywords that work now. The shell's and the dictionary's rows are written with the word the user chose.
    static func offered(in context: SearchContext) -> [KeywordHint] {
        all.filter { $0.isOffered(in: context) }.map { hint in
            let chosen = hint.need == .shell ? context.shell.prefix.rawValue : hint.keyword == WordDefinition.keyword ? context.definitionKeyword : hint.keyword
            guard chosen != hint.keyword else { return hint }
            return KeywordHint(keyword: chosen, example: chosen + hint.example.dropFirst(hint.keyword.count), detail: hint.detail, need: hint.need, takesASpace: hint.takesASpace)
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
        context.text(afterOrAlone: keyword)
    }

    func results(for text: String, context: SearchContext) -> [RootItem] {
        KeywordHint.matching(text, in: KeywordHint.offered(in: context)).map(RootItem.keyword)
    }
}
