//
//  ThawUIStringsGuardTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import SwiftUI
import Testing
import ThawUI

private nonisolated let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The keys a sync has written into the String Catalog.
private nonisolated let catalogKeys: Set<String> = {
    let url = repositoryRoot.appending(path: "Sources/Floe/Resources/Localizable.xcstrings")
    guard let data = try? Data(contentsOf: url), let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let keys = catalog["strings"] as? [String: Any]
    else { return [] }
    return Set(keys.keys)
}()

nonisolated extension LocalizedStringResource {
    /// Whether Floe's catalog has its text: it names the bundle, or its key is one the compiler found, which the
    /// main bundle holds in an Xcode build.
    var readsFloesCatalog: Bool {
        if case let .atURL(url) = bundle, url == Bundle.floe.bundleURL {
            return true
        }
        return catalogKeys.contains(key)
    }
}

/// A literal handed to ThawUI reads the main bundle, which holds Floe's catalog in an Xcode build, so what can go
/// wrong is a key the catalog doesn't have. These hold the words Floe gives by value, and the literals at the call sites.
struct ThawUIStringsGuardTests {
    /// Every resource directly inside a value, by reflection, so a field added later is covered.
    private static func resources(in value: Any) -> [(name: String, resource: LocalizedStringResource)] {
        Mirror(reflecting: value).children.compactMap { child in
            (child.value as? LocalizedStringResource).map { (child.label ?? "?", $0) }
        }
    }

    private static let wordSets: [(String, Any)] = [
        ("HotkeyRecorderStrings", HotkeyRecorderStrings.floe),
        ("PermissionStrings", PermissionStrings.floe),
        ("UpdateConsentStrings", UpdateConsentStrings.floe),
        ("WhatsNewStrings", WhatsNewStrings.floe),
        ("AboutStrings", AboutStrings.floe),
        ("AboutUpdateStrings", AboutUpdateStrings.floe),
        ("AcknowledgementsStrings", AcknowledgementsStrings.floe),
    ]

    @Test func everyWordGivenToThawUIReadsFloesCatalog() {
        for (set, value) in Self.wordSets {
            let found = Self.resources(in: value)
            #expect(!found.isEmpty, "\(set) has no resources to check")
            for (name, resource) in found {
                #expect(resource.readsFloesCatalog, "\(set).\(name) has the key \(resource.key)")
            }
        }
    }

    @Test func wordsMadeFromAValueReadFloesCatalogToo() {
        let made: [LocalizedStringResource] = [
            WhatsNewStrings.floe.releaseTitle("1.0"),
            WhatsNewStrings.floe.releaseTitle("Unreleased"),
            WhatsNewStrings.floe.loadFailed("Floe"),
            WhatsNewStrings.floe.channelName(.beta),
            WhatsNewStrings.floe.calloutName(.note),
            AboutStrings.floe.versionLabel("1", "2", "3"),
            AboutUpdateStrings.floe.lastChecked("today"),
            AboutUpdateStrings.floe.channelName(.beta),
            AboutUpdateStrings.floe.automaticUpdatesName(.check),
            AboutUpdateStrings.floe.automaticUpdatesShortName(.check),
        ]
        #expect(made.filter { !$0.readsFloesCatalog }.isEmpty)
    }

    @Test func tabTitlesReadFloesCatalog() {
        let titles = PrivacyTab.allCases.map(\.title)
        #expect(titles.filter { !$0.readsFloesCatalog }.isEmpty)
    }

    @Test func aResourceFromTheInitializerReadsItsOwnEnglish() {
        #expect(String(localized: HotkeyRecorderStrings.floe.clear) == "Clear")
    }

    @Test(arguments: ["Plain", "%d of %@", "**bold** and [a](b)", "No results for “x”"])
    func verbatimTextComesBackAsWritten(text: String) {
        #expect(String(localized: LocalizedStringResource.verbatim(text)) == text)
    }
}

/// Reads every source file, so it stays off the main actor, where every main actor test in the run would wait for it.
nonisolated struct ThawUIStringsSourceGuardTests {
    /// One call to a ThawUI view whose text parameters take a resource, with its arguments in parentheses.
    private static let textCalls = [
        "ThawSection", "ThawBadge", "ThawEmptyState", "SettingsWarningPill", "SettingsPrivacyNotice", "ThawFirstRunHint",
        "ThawPicker", "ThawMenu", "ThawSlider", "ThawPillPicker", "ThawPillPicker.Option", "ThawSegment", "ThawListHeading",
        "SecondsSliderRow", "SettingsFilterField", "NoMatchesState", "SettingsSearchKeyboard", "AboutMenuItem",
        "OnboardingStepIndicator", "ThawHintTipViewStyle", "ThawCheckboxToggleStyle",
    ]

    /// Parameters that take a name rather than text.
    private static let nonText = ["systemImage:", "symbol:", "image:"]

    private static func sources() throws -> [(path: String, text: String)] {
        let folder = repositoryRoot.appending(path: "Sources/Floe")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return try files.filter { $0.pathExtension == "swift" }.map {
            try ($0.path().replacingOccurrences(of: repositoryRoot.path(), with: ""), String(contentsOf: $0, encoding: .utf8))
        }
    }

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let openParen = UInt8(ascii: "(")
    private static let closeParen = UInt8(ascii: ")")
    private static let dot = UInt8(ascii: ".")

    /// Bytes as text. A slice can cut a character in two, which only the check on what comes before a literal ever does.
    private static func text(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    /// The end of the string literal opening at start, past any interpolation in it.
    private static func endOfLiteral(in text: [UInt8], from start: Int) -> Int {
        var index = start + 1
        while index < text.count {
            if text[index] == backslash, index + 1 < text.count, text[index + 1] == openParen {
                var depth = 1
                index += 2
                while index < text.count, depth > 0 {
                    if text[index] == quote {
                        index = endOfLiteral(in: text, from: index)
                        continue
                    }
                    depth += text[index] == openParen ? 1 : text[index] == closeParen ? -1 : 0
                    index += 1
                }
            } else if text[index] == backslash {
                index += 2
            } else if text[index] == quote {
                return index + 1
            } else {
                index += 1
            }
        }
        return index
    }

    /// The bare string literals among a call's own arguments, leaving out its closures and anything already wrapped
    /// in a call of its own, such as .verbatim(…).
    static func bareLiterals(inCallOpeningAt open: Int, of text: [UInt8]) -> [String] {
        var found: [String] = []
        var index = open + 1
        var parens = 1
        var braces = 0
        while index < text.count, parens > 0 {
            let byte = text[index]
            if byte == quote {
                let end = endOfLiteral(in: text, from: index)
                if parens == 1, braces == 0 {
                    let before = Self.text(text[max(0, index - 16) ..< index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !nonText.contains(where: before.hasSuffix) {
                        found.append(Self.text(text[index ..< end]))
                    }
                }
                index = end
                continue
            }
            switch byte {
            case UInt8(ascii: "{"): braces += 1
            case UInt8(ascii: "}"): braces -= 1
            case openParen where braces == 0: parens += 1
            case closeParen where braces == 0: parens -= 1
            default: break
            }
            index += 1
        }
        return found
    }

    /// Letters, digits, the underscore and anything past ASCII, so a name ending the same as a call is another name.
    private static func isNamePart(_ byte: UInt8) -> Bool {
        byte >= 0x80 || byte == UInt8(ascii: "_") || (byte >= 0x30 && byte <= 0x39) || (byte | 0x20 >= 0x61 && byte | 0x20 <= 0x7A)
    }

    /// One pass over the bytes, looking a name up only where a call opens. This runs over all of Floe's source, where
    /// comparing each name at each character took 14 seconds in a coverage build.
    private static func bareLiterals(in source: String) -> [String] {
        let text = Array(source.utf8)
        let calls = Set(textCalls)
        var found: [String] = []
        var index = 0
        while index < text.count {
            guard isNamePart(text[index]) else {
                index += 1
                continue
            }
            let start = index
            while index < text.count, isNamePart(text[index]) {
                index += 1
            }
            guard index < text.count, text[index] == openParen else { continue }
            var name = Self.text(text[start ..< index])
            if !calls.contains(name), start > 0, text[start - 1] == dot {
                var owner = start - 1
                while owner > 0, isNamePart(text[owner - 1]) {
                    owner -= 1
                }
                name = Self.text(text[owner ..< index])
            }
            if calls.contains(name) {
                found += bareLiterals(inCallOpeningAt: index, of: text)
            }
        }
        return found
    }

    @Test func theScanFindsABareLiteralAndLeavesTheRest() {
        #expect(Self.bareLiterals(in: #"ThawSection("Bare") { Text("Inside") }"#) == [#""Bare""#])
        #expect(Self.bareLiterals(in: #"ThawEmptyState(systemImage: "doc", title: "No \(thing("x"))")"#) == [#""No \(thing("x"))""#])
        #expect(Self.bareLiterals(in: #"ThawBadge(.verbatim("Fine"), tone: .neutral)"#).isEmpty)
        #expect(Self.bareLiterals(in: #"ThawBadge(flag ? "One" : "Two")"#).count == 2)
    }

    /// The compiler must find what a call gives ThawUI, or a translator never sees it. The catalog is what a sync wrote.
    @Test func everyLiteralGivenToThawUIIsInTheCatalog() throws {
        let sources = try Self.sources()
        // A moved folder or renamed views would otherwise scan nothing and pass.
        #expect(sources.count > 100)
        var scanned = 0
        var missing: [String] = []
        for (path, text) in sources {
            for literal in Self.bareLiterals(in: text) {
                scanned += 1
                // An interpolated key has placeholders only the compiler can spell.
                guard !literal.contains("\\(") else { continue }
                let key = String(literal.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
                if !catalogKeys.contains(key) {
                    missing.append("\(path): \(key)")
                }
            }
        }
        #expect(scanned > 80, "Only \(scanned) literals found")
        #expect(missing.isEmpty, "Run ./scripts/sync-strings.sh: \(missing.joined(separator: ", "))")
    }

    @Test func aResourceWrittenOutNamesTheBundle() throws {
        // Over the code only: a comment may quote the form, and Localization.swift is what supplies the bundle.
        for (path, text) in try Self.sources() {
            for line in text.components(separatedBy: "\n") where line.contains("LocalizedStringResource(\"") && !line.contains("//") {
                #expect(line.contains("bundle: .floe") || text.contains("bundle: .floe,"), "\(path): \(line)")
            }
        }
    }
}
