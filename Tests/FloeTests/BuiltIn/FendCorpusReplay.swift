//
//  FendCorpusReplay.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import FendCore
@testable import Floe
import Foundation

/// Replay harness for the calculator, after Thaw's log replay: each input of fend's own tests is given to Floe as if typed.
/// What Floe shows has to be what fend's tests expect, except the cases FendCorpusLedger holds, and the ledger has to stay true.
enum FendCorpusReplay {
    /// One call from fend's tests: an input and the answer expected for it.
    struct Case: Equatable {
        let input: String
        let expected: String
    }

    /// What became of an input.
    enum Verdict: Equatable {
        /// Floe shows fend's answer, or leaves out what it leaves out on purpose.
        case same
        /// The wrapper around fend does not give the answer fend's tests expect, so Floe cannot either.
        case engine(String)
        /// fend answers and Floe shows no calculator at all.
        case notShown
        /// Floe shows the calculator with an error, or with nothing in it.
        case refused(String)
        /// Floe shows something else.
        case different(String)

        /// The verdict as the ledger writes it, or nil when there is nothing to write down.
        var ledgerEntry: (kind: String, shown: String)? {
            switch self {
            case .same: nil
            case let .engine(answer): ("engine", answer)
            case .notShown: ("not shown", "")
            case let .refused(message): ("refused", message)
            case let .different(shown): ("different", shown)
            }
        }
    }

    // MARK: Parsing

    /// A Rust string literal. An escape may be a line break, which is how a long literal is carried over.
    private static let literal = #""((?:[^"\\]|\\[\s\S])*)""#
    private static let call = #"\b(?:test_eval|test_eval_simple)\(\s*"# + literal + #"\s*,\s*"# + literal + #"\s*,?\s*\)"#

    /// Every call in the fixture, in the order fend's tests have them.
    static func parse(_ text: String) -> [Case] {
        guard let pattern = try? NSRegularExpression(pattern: call) else { return [] }
        let source = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            Case(input: unescaped(source.substring(with: match.range(at: 1))), expected: unescaped(source.substring(with: match.range(at: 2))))
        }
    }

    /// The text a Rust string literal stands for.
    static func unescaped(_ literal: String) -> String {
        var text = ""
        var rest = Substring(literal)
        while let character = rest.popFirst() {
            guard character == "\\", let escape = rest.popFirst() else {
                text.append(character)
                continue
            }
            switch escape {
            case "n": text.append("\n")
            case "r": text.append("\r")
            case "t": text.append("\t")
            case "0": text.append("\0")
            case "x":
                text.append(scalar(hex: rest.prefix(2)))
                rest = rest.dropFirst(2)
            case "u":
                let digits = rest.dropFirst().prefix { $0 != "}" }
                text.append(scalar(hex: digits))
                rest = rest.dropFirst(digits.count + 2)
            case "\n", "\r\n":
                // A backslash at the end of a line joins it to the next, without that line's indentation.
                rest = rest.drop { $0.isWhitespace }
            default:
                text.append(escape)
            }
        }
        return text
    }

    private static func scalar(hex: Substring) -> String {
        UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
    }

    // MARK: Replaying

    /// The answer as Floe words it: an inexact answer carries a sign where fend writes "approx.".
    static func presented(_ answer: String) -> String {
        answer.replacingOccurrences(of: "approx. ", with: "≈ ")
    }

    /// The ways Floe may write fend's answer and still be saying the same thing. Each is a choice made for
    /// the reader, and none of them touches a digit.
    static func isSameAnswer(shown: String, expected: String, input: String) -> Bool {
        let answer = presented(expected)
        return shown == answer
            || shown == percentagesOfTheLeftSide[input]
            || shown == withTightUnitDivision(answer)
            || isSameInItsBase(shown: shown, answer: answer)
            || shown == decimalValue(ofLiteral: input)
    }

    /// Where Floe answers differently on purpose: a percentage beside an amount is that much of the amount,
    /// as a person means it, where fend adds or multiplies a hundredth. The cases of fend's tests this reaches.
    static let percentagesOfTheLeftSide = ["0.1 + 5%": "0.105", "5% * 100": "5"]

    /// A unit divided by a unit is written without the spaces fend puts round the stroke: m/s for m / s.
    static func withTightUnitDivision(_ answer: String) -> String {
        answer.replacingOccurrences(of: " / ", with: "/")
    }

    /// A number in another base carries its base below the line, not as a prefix, and hexadecimal is in
    /// capitals: F₁₆ for 0xf, 10000₂ for the 10000 that "to base 2" gives. The digits have to be fend's.
    static func isSameInItsBase(shown: String, answer: String) -> Bool {
        guard shown.unicodeScalars.contains(where: isSubscriptDigit) else { return false }
        let digits = String(String.UnicodeScalarView(shown.unicodeScalars.filter { !isSubscriptDigit($0) }))
        let unprefixed = answer.replacingOccurrences(of: #"\b0[xbo](?=[0-9a-fA-F])"#, with: "", options: .regularExpression)
        return digits.lowercased() == unprefixed.lowercased()
    }

    private static func isSubscriptDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x2080 ... 0x2089).contains(scalar.value)
    }

    /// A number typed alone in another base is answered in decimal, where fend gives the number back.
    static func decimalValue(ofLiteral input: String) -> String? {
        let typed = input.trimmingCharacters(in: .whitespaces)
        guard typed.wholeMatch(of: /0[xXbBoO][0-9a-fA-F_]+/) != nil else { return nil }
        return (try? FendContext().evaluate("\(typed) to decimal") as FendResult)?.string
    }

    /// A number typed alone, or nothing at all, is not a calculation: Floe shows no calculator for it.
    static func isNotACalculation(_ input: String) -> Bool {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty || typed.allSatisfy { $0.isNumber || $0 == "." || $0 == "," || $0 == "_" }
    }

    /// Gives the input to fend through the wrapper, then to a calculator of its own, as the search does.
    static func verdict(for replayed: Case) -> Verdict {
        let context = try? FendContext()
        let answer = (try? context?.evaluate(replayed.input) as FendResult?)?.string
        guard answer == replayed.expected else { return .engine(answer ?? "error") }
        guard let preview = Calculator().evaluatePreview(replayed.input) else {
            return isNotACalculation(replayed.input) ? .same : .notShown
        }
        if let error = preview.error {
            return .refused(error)
        }
        if preview.result.isEmpty {
            return .refused("")
        }
        return isSameAnswer(shown: preview.result, expected: replayed.expected, input: replayed.input) ? .same : .different(preview.result)
    }

    // MARK: What is drawn

    /// What the view draws for an input, as text with each change of colour marked, or nil when no result is drawn.
    /// In one fixed locale, so that the record reads the same on every machine.
    static func drawn(for replayed: Case) -> String? {
        guard verdict(for: replayed) == .same, let preview = Calculator().evaluatePreview(replayed.input), !preview.result.isEmpty else { return nil }
        let styled = CalculatorFormatter.formatResult(spans: preview.spans, query: replayed.input, locale: Locale(identifier: "en_US"))
        return styled.runs.map { run in
            let text = String(styled[run.range].characters)
            return run.foregroundColor.map { "\(text)⟨\($0)⟩" } ?? text
        }.joined()
    }

    /// One line of the record of what is drawn: the input, then the drawn text.
    static func drawnRecord(of cases: [Case]) -> [String] {
        cases.compactMap { replayed in drawn(for: replayed).map { [replayed.input, $0].map(escaped).joined(separator: "\t") } }
    }

    static func drawnFile(from testFile: String = #filePath) -> URL {
        URL(fileURLWithPath: testFile).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/FendCorpusDrawn.swift")
    }

    static func drawnSource(_ lines: [String]) -> String {
        """
        //
        //  FendCorpusDrawn.swift
        //  Project: Floe
        //
        //  Copyright (Floe) © 2026 René Jiménez
        //  Licensed under the GNU AGPLv3
        //
        //  Written by the replay suite when FLOE_WRITE_FEND_LEDGER=1. Do not add a line by hand.

        /// What the calculator draws for each input of fend's tests it answers, one to a line: the input, a tab, the text.
        /// A change of colour is marked after the text it applies to. A change to a line is a change to what people see.
        enum FendCorpusDrawn {
            static let text = ##\"\"\"
        \(lines.map { "    " + $0 }.joined(separator: "\n"))
            \"\"\"##
        }

        """
    }

    // MARK: Ledger

    /// One line of the ledger: what kind of difference, the input, fend's answer, and what Floe shows.
    static func ledgerLine(for replayed: Case, _ verdict: Verdict) -> String? {
        guard let entry = verdict.ledgerEntry else { return nil }
        return [entry.kind, replayed.input, replayed.expected, entry.shown].map(escaped).joined(separator: "\t")
    }

    /// Every difference there is now, as the ledger would hold it.
    static func currentLedger(of cases: [Case]) -> [String] {
        cases.compactMap { ledgerLine(for: $0, verdict(for: $0)) }
    }

    /// The lines the ledger holds, without the blank ones.
    static func lines(ofLedger text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// A field on one line: a tab, a line break and a backslash are written as escapes.
    static func escaped(_ field: String) -> String {
        field.unicodeScalars.reduce(into: "") { text, scalar in
            switch scalar {
            case "\\": text += "\\\\"
            case "\t": text += "\\t"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: text += "\\x" + String(format: "%02x", scalar.value)
            default: text.unicodeScalars.append(scalar)
            }
        }
    }

    /// Where the ledger is kept, beside the fixture, for the run that rewrites it.
    static func ledgerFile(from testFile: String = #filePath) -> URL {
        URL(fileURLWithPath: testFile).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/FendCorpusLedger.swift")
    }

    /// The ledger as a Swift file, written from the differences there are now.
    static func ledgerSource(_ lines: [String]) -> String {
        """
        //
        //  FendCorpusLedger.swift
        //  Project: Floe
        //
        //  Copyright (Floe) © 2026 René Jiménez
        //  Licensed under the GNU AGPLv3
        //
        //  Written by the replay suite when FLOE_WRITE_FEND_LEDGER=1. Do not add a line by hand.

        /// Where Floe's calculator does not show what fend's own tests expect, one case to a line, with tabs
        /// between: the kind of difference, the input, fend's answer and what Floe shows.
        ///
        ///   engine     the wrapper does not give fend's answer, so Floe cannot
        ///   not shown  fend answers and Floe shows no calculator
        ///   refused    Floe shows the calculator with an error, or empty
        ///   different  Floe shows something else
        enum FendCorpusLedger {
            static let text = ##\"\"\"
        \(lines.map { "    " + $0 }.joined(separator: "\n"))
            \"\"\"##
        }

        """
    }
}
