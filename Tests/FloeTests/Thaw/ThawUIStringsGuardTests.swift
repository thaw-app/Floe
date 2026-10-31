//
//  ThawUIStringsGuardTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing
import ThawUI

extension LocalizedStringResource {
    /// Whether it reads Floe's catalog, not the main bundle a resource with no bundle reads.
    var namesFloesBundle: Bool {
        if case let .atURL(url) = bundle {
            return url == Bundle.floe.bundleURL
        }
        return false
    }
}

/// A bare literal handed to ThawUI compiles and reads the main bundle, which is not where a `swift build` keeps Floe's
/// catalog, so neither the compiler nor a review sees it. These hold every call to Floe's bundle: the words Floe gives
/// by value, and over the source, the literals at the call sites.
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

    @Test func everyWordGivenToThawUINamesFloesBundle() {
        for (set, value) in Self.wordSets {
            let found = Self.resources(in: value)
            #expect(!found.isEmpty, "\(set) has no resources to check")
            for (name, resource) in found {
                #expect(resource.namesFloesBundle, "\(set).\(name) reads \(resource.bundle)")
            }
        }
    }

    @Test func wordsMadeFromAValueNameFloesBundleToo() {
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
        #expect(made.filter { !$0.namesFloesBundle }.isEmpty)
    }

    @Test func tabTitlesNameFloesBundle() {
        let titles = PrivacyTab.allCases.map(\.title)
        #expect(titles.filter { !$0.namesFloesBundle }.isEmpty)
    }

    /// The catalog's plural form is only reachable by actually finding the catalog: English keeps the key otherwise.
    @Test func aResourceFromTheHelperReadsTheCatalog() {
        #expect(String(localized: LocalizedStringResource.floe("\(1) results")) == "1 result")
        #expect(String(localized: LocalizedStringResource.floe("\(2) results")) == "2 results")
    }

    @Test func aResourceFromTheInitializerReadsItsOwnEnglish() {
        #expect(String(localized: HotkeyRecorderStrings.floe.clear) == "Clear")
    }

    @Test(arguments: ["Plain", "%d of %@", "**bold** and [a](b)", "No results for “x”"])
    func verbatimTextComesBackAsWritten(text: String) {
        #expect(String(localized: LocalizedStringResource.verbatim(text)) == text)
    }
}

/// Reads every source file, so it stays off the main actor: the test target's default isolation would otherwise put
/// it there, and every main actor test in the run would wait for it.
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

    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func sources() throws -> [(path: String, text: String)] {
        let folder = root.appending(path: "Sources/Floe")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return try files.filter { $0.pathExtension == "swift" }.map {
            try ($0.path().replacingOccurrences(of: root.path(), with: ""), String(contentsOf: $0, encoding: .utf8))
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

    /// The end of the string literal opening at `start`, past any interpolation in it.
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
    /// in a call of its own, such as `.floe(…)`.
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
        #expect(Self.bareLiterals(in: #"ThawBadge(.floe("Fine"), tone: .neutral)"#).isEmpty)
        #expect(Self.bareLiterals(in: #"ThawBadge(flag ? "One" : "Two")"#).count == 2)
    }

    @Test func noCallToThawUIHandsItABareLiteral() throws {
        let sources = try Self.sources()
        // A moved folder would otherwise scan nothing and pass.
        #expect(sources.count > 100)
        var violations: [String] = []
        for (path, text) in sources {
            violations += Self.bareLiterals(in: text).map { "\(path): \($0)" }
        }
        #expect(violations.isEmpty, "Name Floe's bundle with .floe(…) or .verbatim(…): \(violations.joined(separator: ", "))")
    }

    @Test func aResourceWrittenOutNamesTheBundle() throws {
        // Over the code only: a comment may quote the form, and Localization.swift is what supplies the bundle.
        for (path, text) in try Self.sources() {
            for line in text.components(separatedBy: "\n") where line.contains("LocalizedStringResource(\"") && !line.contains("//") {
                #expect(line.contains("bundle: .floe") || text.contains("bundle: .floe,"), "\(path): \(line)")
            }
        }
    }

    /// The compiler must find what the helper wraps, or a translator never sees it. The catalog is what a sync wrote.
    @Test func everyKeyGivenToTheHelperIsInTheCatalog() throws {
        let catalogURL = Self.root.appending(path: "Sources/Floe/Resources/Localizable.xcstrings")
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let keys = try #require(catalog["strings"] as? [String: Any])
        var missing: [String] = []
        for (path, text) in try Self.sources() {
            for match in text.matches(of: /\.floe\("((?:[^"\\]|\\.)*)"\)/) {
                let raw = String(match.output.1)
                // An interpolated key has placeholders only the compiler can spell.
                guard !raw.contains("\\(") else { continue }
                let key = raw.replacingOccurrences(of: "\\\"", with: "\"")
                if keys[key] == nil {
                    missing.append("\(path): \(key)")
                }
            }
        }
        #expect(missing.isEmpty, "Run ./scripts/sync-strings.sh: \(missing.joined(separator: ", "))")
    }
}
