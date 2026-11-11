//
//  Translate.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import NaturalLanguage

// Its types are not marked Sendable yet; each is made and used inside one call.
@preconcurrency import Translation

/// "translate hola mundo" and "translate to german good morning", by the translation macOS does on the Mac.
/// The translation is Apple's and can be rough, and the row says both.
nonisolated enum Translate {
    static let keyword = "translate"
    /// Where the languages are downloaded: Language & Region, under Translation Languages.
    static let settingsLink = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")

    /// What was typed, split into the language asked for and the text.
    struct Request: Equatable {
        var text: String
        var target: Locale.Language?
    }

    enum Outcome: Equatable {
        case translated(String, from: Locale.Language, to: Locale.Language)
        /// macOS knows the pair and has not downloaded it.
        case notDownloaded(from: Locale.Language, to: Locale.Language)
        /// The text's language could not be told, or macOS does not translate it.
        case unknownLanguage
        /// The text is in the language it would be translated to, and no other was named.
        case alreadyIn(Locale.Language)
        case failed
    }

    enum Readiness {
        case installed, downloadable, unsupported
    }

    /// What does the translating, so a test can stand in for macOS.
    struct Engine: Sendable {
        var languages: @Sendable () async -> [Locale.Language]
        var readiness: @Sendable (_ source: Locale.Language, _ target: Locale.Language) async -> Readiness
        var translate: @Sendable (_ text: String, _ source: Locale.Language, _ target: Locale.Language) async throws -> String
        var detect: @Sendable (String) -> Locale.Language?

        static let apple = Engine(
            languages: { await LanguageAvailability().supportedLanguages },
            readiness: { source, target in
                switch await LanguageAvailability().status(from: source, to: target) {
                case .installed: .installed
                case .supported: .downloadable
                default: .unsupported
                }
            },
            translate: { text, source, target in
                try await TranslationSession(installedSource: source, target: target).translate(text).targetText
            },
            detect: { NLLanguageRecognizer.dominantLanguage(for: $0).map { Locale.Language(identifier: $0.rawValue) } }
        )
    }

    /// A language without its region, which is how two of them are told apart here: Spanish is one, Chinese is two.
    static func plain(_ language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        return code == "zh" ? "zh-\(language.script?.identifier ?? "Hans")" : code
    }

    /// The words a language answers to: its code, and its name in English, in the user's language and in its own.
    static func names(of languages: [Locale.Language], locale: Locale = .current) -> [String: Locale.Language] {
        var names: [String: Locale.Language] = [:]
        for code in Set(languages.map(plain)).sorted() {
            let language = Locale.Language(identifier: code)
            let spoken = [Locale(identifier: "en"), locale, Locale(identifier: code)].compactMap { $0.localizedString(forIdentifier: code) }
            for name in [code] + spoken {
                // The first word, so "Chinese, Simplified" answers to "chinese"; the first language to claim a word keeps it.
                let word = name.lowercased().split { !$0.isLetter && $0 != "-" }.first.map(String.init) ?? ""
                if !word.isEmpty, names[word] == nil {
                    names[word] = language
                }
            }
        }
        return names
    }

    /// "to german good morning" names its language; anything else is all text.
    static func request(from typed: String, names: [String: Locale.Language]) -> Request {
        let words = typed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard words.count == 3, words[0].lowercased() == "to", let target = names[words[1].lowercased()] else {
            return Request(text: typed.trimmingCharacters(in: .whitespacesAndNewlines), target: nil)
        }
        return Request(text: String(words[2]).trimmingCharacters(in: .whitespacesAndNewlines), target: target)
    }

    /// Without a language named: the first of the user's languages that the text is not in already.
    static func target(for source: Locale.Language, preferred: [String]) -> Locale.Language? {
        preferred.map { Locale.Language(identifier: $0) }.first { plain($0) != plain(source) }
    }

    static func outcome(for typed: String, engine: Engine = .apple, preferred: [String] = Locale.preferredLanguages, locale: Locale = .current) async -> Outcome {
        let languages = await engine.languages()
        let request = request(from: typed, names: names(of: languages, locale: locale))
        guard !request.text.isEmpty else { return .failed }
        let known = Set(languages.map(plain))
        guard let source = engine.detect(request.text), known.contains(plain(source)) else { return .unknownLanguage }
        guard let target = request.target ?? target(for: source, preferred: preferred), plain(target) != plain(source) else { return .alreadyIn(source) }
        switch await engine.readiness(source, target) {
        case .unsupported:
            return .unknownLanguage
        case .downloadable:
            return .notDownloaded(from: source, to: target)
        case .installed:
            guard let text = try? await engine.translate(request.text, source, target), !text.isEmpty else { return .failed }
            return .translated(text, from: source, to: target)
        }
    }

    /// The row for an outcome. Every one names Apple as the translator; nil when there is nothing to say.
    static func row(for outcome: Outcome, locale: Locale = .current) -> AnswerRow? {
        let name: (Locale.Language) -> String = { locale.localizedString(forIdentifier: plain($0)) ?? plain($0) }
        let kind = String(localized: "Apple Translation", bundle: .floe, comment: "The kind of a result, shown beside its title. Here a text translated by macOS's own translation.")
        switch outcome {
        case let .translated(text, from, to):
            return AnswerRow(
                id: "translate",
                text: text,
                subtitle: String(localized: "\(name(from)) to \(name(to)), by Apple's translation on this Mac. It can be rough.", bundle: .floe, comment: "Under a translated text. Both placeholders are names of languages."),
                kind: kind,
                symbol: "translate"
            )
        case let .notDownloaded(from, to):
            var row = AnswerRow(
                id: "translate",
                text: String(localized: "\(name(from)) to \(name(to)) is not downloaded", bundle: .floe, comment: "Both placeholders are names of languages. macOS downloads each pair of languages it translates between."),
                subtitle: String(localized: "Return opens Language & Region, where Translation Languages downloads it.", bundle: .floe, comment: "Language & Region and Translation Languages are named as System Settings names them."),
                kind: kind,
                symbol: "arrow.down.circle"
            )
            row.link = settingsLink
            row.linkTitle = String(localized: "Open System Settings", bundle: .floe)
            return row
        case .unknownLanguage:
            return AnswerRow(
                id: "translate",
                text: String(localized: "Apple's translation does not know this language", bundle: .floe),
                subtitle: String(localized: "Ask AI can translate it, when an AI source is set.", bundle: .floe, comment: "Ask AI is the name of a command of Floe."),
                kind: kind,
                symbol: "questionmark.circle"
            )
        case let .alreadyIn(language):
            return AnswerRow(
                id: "translate",
                text: String(localized: "This is already \(name(language))", bundle: .floe, comment: "The placeholder is the name of a language."),
                subtitle: String(localized: "Name the language: translate to german good morning", bundle: .floe, comment: "The words after the colon are typed as they are and stay in English."),
                kind: kind,
                symbol: "questionmark.circle"
            )
        case .failed:
            return nil
        }
    }
}

/// The scope waits for the typing to rest before it asks, so a sentence is translated once and not once a letter.
struct TranslateSearchScope: SearchScope {
    let keyword = Translate.keyword
    let title = String(localized: "Translation", bundle: .floe, comment: "The heading over a translated text.")
    let emptyTitle = String(localized: "Nothing to translate", bundle: .floe)
    var engine = Translate.Engine.apple
    var clipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    var pause = Duration.milliseconds(300)

    /// The word alone translates the clipboard.
    func text(in context: SearchContext) -> String? {
        context.text(afterOrAlone: keyword)
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        let typed = text.isEmpty ? clipboard() ?? "" : text
        return .once(after: pause) { [engine] in
            await Translate.row(for: Translate.outcome(for: typed, engine: engine)).map { [.answer($0)] } ?? []
        }
    }
}
