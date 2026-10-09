//
//  LocalizationTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing

/// The String Catalog as it is on disk, read from the checkout the tests were built from.
private nonisolated struct Catalog: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let localizations: [String: Localization]?
        let extractionState: String?

        /// The code gives this key its English apart, because the same English means something else elsewhere.
        var hasItsOwnEnglish: Bool {
            extractionState == "extracted_with_value"
        }
    }

    struct Localization: Decodable, Sendable {
        let stringUnit: Unit?
        let variations: Variations?
    }

    struct Variations: Decodable, Sendable {
        let plural: [String: Localization]?
    }

    struct Unit: Decodable, Sendable {
        let value: String
    }

    let sourceLanguage: String
    let strings: [String: Entry]

    static let onDisk: Catalog? = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Floe/Resources/Localizable.xcstrings")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Catalog.self, from: $0) }
    }()

    static let keys = (onDisk?.strings.keys.sorted()) ?? []

    static func english(_ key: String) -> Localization? {
        onDisk?.strings[key]?.localizations?["en"]
    }
}

struct LocalizationCatalogTests {
    @Test func theCatalogIsEnglishOnly() throws {
        let catalog = try #require(Catalog.onDisk)
        #expect(catalog.sourceLanguage == "en")
        #expect(!catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            let languages = entry.localizations?.keys.sorted() ?? []
            #expect(languages.allSatisfy { $0 == "en" }, "\(key) has \(languages)")
        }
    }

    /// English is the key. The catalog only restates it to number two placeholders, to give plural forms,
    /// or where the code names a key apart from its English.
    @Test(arguments: Catalog.keys)
    func everyKeyResolvesToItsEnglishSource(key: String) throws {
        let resolved = Bundle.floe.localizedString(forKey: key, value: nil, table: nil)
        guard let english = Catalog.english(key) else {
            #expect(resolved == key)
            return
        }
        if Catalog.onDisk?.strings[key]?.hasItsOwnEnglish == true {
            // The English is the default value in the code; a compiled catalog leaves untranslated entries out.
            let unit = try #require(english.stringUnit)
            #expect(!unit.value.isEmpty)
            #expect(unit.value != key)
        } else if let unit = english.stringUnit {
            #expect(unit.value.replacing(/%\d+\$/, with: "%") == key)
            #expect(resolved.replacing(/%\d+\$/, with: "%") == key)
        } else {
            let plural = try #require(english.variations?.plural)
            #expect(plural["other"]?.stringUnit?.value == key)
            #expect(plural["one"]?.stringUnit != nil)
        }
    }

    @Test func thePluralKeysAreTheOnesTheCodeCounts() {
        #expect(Catalog.keys.filter { Catalog.english($0)?.variations != nil } == [
            "%lld characters", "%lld commands", "%lld files", "%lld items", "%lld names, %@", "%lld results", "%lld tabs", "From Raycast · %lld commands",
        ])
    }
}

struct LocalizedTextTests {
    @Test(arguments: [(0, "0 items"), (1, "1 item"), (2, "2 items"), (40, "40 items")])
    func aCountTakesItsPluralFormFromTheCatalog(total: Int, label: String) {
        #expect(PickList.countLabel(shown: total, total: total, isFiltered: false) == label)
    }

    @Test func valuesGoIntoAWholeSentence() {
        #expect(PickList.countLabel(shown: 3, total: 40, isFiltered: true) == "3 of 40")
        #expect(RootItem.searchFiles("tax 100%").title == "Search Files for \"tax 100%\"")
        #expect(RootItem.askAI("is %@ a word").title == "Ask AI \u{201C}is %@ a word\u{201D}")
    }

    @Test(arguments: [
        ("", "small", "key", String?.none),
        ("ftp://x", "small", "key", "AI can't answer yet. It needs an address that starts with http:// or https://."),
        ("https://api.test/v1", " ", "key", "AI can't answer yet. It needs a model."),
        ("https://api.test/v1", "small", "", "AI can't answer yet. It needs an API key."),
        ("ftp://x", "", "key", "AI can't answer yet. It needs an address that starts with http:// or https:// and a model."),
        ("https://api.test/v1", "", " ", "AI can't answer yet. It needs a model and an API key."),
    ])
    func whatAnAPISetupNeedsIsOneSentence(baseURL: String, model: String, apiKey: String, problem: String?) {
        #expect(AIEndpoint.problem(baseURL: baseURL, model: model, apiKey: apiKey) == problem)
    }
}

/// Text an extension or the user wrote reaches views that only take a key. It must be shown as written.
struct VerbatimTextTests {
    static nonisolated let texts = ["100%", "%@", "%lld items", "Cancel", "**bold** and _more_", "50% off %d things", "[link](https://example.com)"]

    @Test(arguments: texts)
    func textThatIsNotFloesIsAnArgumentAndNeverAKey(text: String) {
        let key = LocalizedStringKey.verbatim(text)
        #expect(key != LocalizedStringKey(text))
        #expect(Text(key)._resolveText(in: EnvironmentValues()) == text)
    }

    @Test(arguments: texts)
    func aRowKeepsAnExtensionsTitleAsWritten(text: String) {
        let link = Quicklink(name: text, keyword: "x", url: "https://example.com")
        #expect(RootItem.quicklink(link, queryText: "", fallback: false, keywordSearch: false).title == text)
    }
}

struct LocalizedSearchTests {
    /// A title is matched in the language it is shown in, which is the one the row was built with.
    @Test func searchingByATitleFindsTheRow() {
        let rows: [RootItem] = [.fileSearch, .menuBarSearch, .emojiSearch, .clipboardHistory, .settings]
        for item in rows {
            let results = Ranking.search(rows, query: item.title, favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
            #expect(results.first?.item.id == item.id)
        }
    }

    @Test func idsAndScopeKeywordsAreNotText() {
        #expect(RootItem.fileSearch.settingsKey == "builtin:file-search")
        #expect(ClipboardSearchScope().keyword == "clipboard")
        #expect(SSHSearchScope().keyword == "ssh")
        #expect(AppleShortcutSearchScope().keyword == "shortcuts")
    }
}
