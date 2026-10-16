//
//  TranslateTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct TranslateTests {
    private static let spanish = Locale.Language(identifier: "es")
    private static let english = Locale.Language(identifier: "en")
    private static let german = Locale.Language(identifier: "de")
    private let englishLocale = Locale(identifier: "en_US")

    /// A translator that knows Spanish, English, German and both Chineses, has German to download, and answers in capitals.
    private func engine(detects language: Locale.Language? = TranslateTests.spanish, asked: CallLog? = nil) -> Translate.Engine {
        Translate.Engine(
            languages: { ["es-MX", "es-ES", "en-US", "de-DE", "zh-Hans-CN", "zh-Hant-TW"].map { Locale.Language(identifier: $0) } },
            readiness: { _, target in Translate.plain(target) == "de" ? .downloadable : .installed },
            translate: { text, source, target in
                asked?.note("\(Translate.plain(source))>\(Translate.plain(target)): \(text)")
                return text.uppercased()
            },
            detect: { _ in language }
        )
    }

    private func outcome(_ typed: String, detects language: Locale.Language? = TranslateTests.spanish, preferred: [String] = ["en-US", "es-MX"]) async -> Translate.Outcome {
        await Translate.outcome(for: typed, engine: engine(detects: language), preferred: preferred, locale: englishLocale)
    }

    @Test func aLanguageAnswersToItsCodeAndItsNames() {
        let names = Translate.names(of: ["es-MX", "es-ES", "de-DE", "zh-Hans-CN", "zh-Hant-TW"].map { Locale.Language(identifier: $0) }, locale: englishLocale)
        #expect(names["german"].map(Translate.plain) == "de")
        #expect(names["deutsch"].map(Translate.plain) == "de")
        #expect(names["de"].map(Translate.plain) == "de")
        #expect(names["spanish"].map(Translate.plain) == "es")
        #expect(names["español"].map(Translate.plain) == "es")
        #expect(names["chinese"].map(Translate.plain) == "zh-Hans", "the first to claim a word keeps it")
        #expect(names["klingon"] == nil)
    }

    @Test func aLanguageIsNamedOnlyByToAndAWordThatIsOne() {
        let names = Translate.names(of: [Self.german, Self.spanish], locale: englishLocale)
        #expect(Translate.request(from: "to german good morning", names: names) == .init(text: "good morning", target: Self.german))
        #expect(Translate.request(from: "To Deutsch good morning", names: names).target == Self.german)
        #expect(Translate.request(from: "to the moon and back", names: names) == .init(text: "to the moon and back", target: nil))
        #expect(Translate.request(from: "to german", names: names).target == nil, "with no text after it, it is the text")
        #expect(Translate.request(from: "  hola  ", names: names) == .init(text: "hola", target: nil))
    }

    @Test func theTextGoesToTheUsersFirstLanguageItIsNotAlreadyIn() async {
        #expect(await outcome("hola mundo") == .translated("HOLA MUNDO", from: Self.spanish, to: Locale.Language(identifier: "en-US")))
        #expect(await outcome("good morning", detects: Self.english) == .translated("GOOD MORNING", from: Self.english, to: Locale.Language(identifier: "es-MX")))
        #expect(await outcome("good morning", detects: Self.english, preferred: ["en-US"]) == .alreadyIn(Self.english))
        #expect(await outcome("to spanish hola", detects: Self.spanish) == .alreadyIn(Self.spanish))
    }

    @Test func whatCannotBeTranslatedSaysWhy() async {
        #expect(await outcome("to german hola mundo") == .notDownloaded(from: Self.spanish, to: Self.german))
        #expect(await outcome("saluton mondo", detects: Locale.Language(identifier: "eo")) == .unknownLanguage)
        #expect(await outcome("???", detects: nil) == .unknownLanguage)
        #expect(await outcome("   ") == .failed)
    }

    @Test func everyRowSaysTheTranslationIsApples() throws {
        let done = try #require(Translate.row(for: .translated("hello world", from: Self.spanish, to: Self.english), locale: englishLocale))
        #expect(done.text == "hello world")
        #expect(done.kind == "Apple Translation")
        #expect(done.subtitle == "Spanish to English, by Apple's translation on this Mac. It can be rough.")
        #expect(done.link == nil)
        #expect(done.id == "answer:translate", "the id never holds the text")

        let missing = try #require(Translate.row(for: .notDownloaded(from: Self.spanish, to: Self.german), locale: englishLocale))
        #expect(missing.text == "Spanish to German is not downloaded")
        #expect(missing.link == Translate.settingsLink)
        #expect(FoundRows().returnTitle(for: .answer(missing)) == "Open System Settings")
        var elsewhere = missing
        elsewhere.linkTitle = nil
        #expect(FoundRows().returnTitle(for: .answer(elsewhere)) == "Open", "a link with no title of its own is just opened")
        #expect(missing.kind == "Apple Translation")

        #expect(Translate.row(for: .alreadyIn(Self.english), locale: englishLocale)?.text == "This is already English")
        #expect(Translate.row(for: .unknownLanguage, locale: englishLocale)?.text == "Apple's translation does not know this language")
        #expect(Translate.row(for: .failed, locale: englishLocale) == nil)
    }

    @MainActor @Test func theScopeTranslatesWhatIsTypedOrTheClipboardAndReturnOpensSettingsForAMissingLanguage() async throws {
        let asked = CallLog()
        let scope = TranslateSearchScope(engine: engine(asked: asked), clipboard: { "del portapapeles" }, pause: .zero)
        #expect(scope.text(in: SearchContext(query: "translate hola")) == "hola")
        #expect(scope.text(in: SearchContext(query: "Translate")) == "")
        #expect(scope.text(in: SearchContext(query: "translated")) == nil)
        func rows(_ text: String) async throws -> [RootItem] {
            var last: [RootItem] = []
            for await batch in try #require(scope.updates(for: text, context: SearchContext(query: "translate " + text))) {
                last = batch
            }
            return last
        }
        _ = try await rows("hola mundo")
        _ = try await rows("")
        #expect(asked.all.map { $0.split(separator: ": ").last.map(String.init) } == ["hola mundo", "del portapapeles"])
        let missing = try #require(try await rows("to german hola").first)
        #expect(FoundRows().returnTitle(for: missing) == "Open System Settings")
        #expect(missing.isScopeResult)
        let done = try #require(try await rows("hola").first)
        #expect(FoundRows().returnTitle(for: done) == "Copy to Clipboard")
        #expect(done.kind == "Apple Translation")
    }

    @MainActor @Test func aSearchThatMovesOnIsNotTranslated() async throws {
        let asked = CallLog()
        let scope = TranslateSearchScope(engine: engine(asked: asked), clipboard: { nil }, pause: .seconds(30))
        let stream = try #require(scope.updates(for: "hola", context: SearchContext(query: "translate hola")))
        let reading = Task {
            for await _ in stream {
                // Nothing arrives before the pause is over.
            }
        }
        reading.cancel()
        await reading.value
        try await Task.sleep(for: .milliseconds(50))
        #expect(asked.all.isEmpty)
    }
}
