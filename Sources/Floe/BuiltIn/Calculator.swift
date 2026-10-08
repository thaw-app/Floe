//
//  Calculator.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

/// Represents the preview state of a calculation query.
struct CalculationPreview: Equatable {
    let result: String
    let spans: [FendSpan]
    let attributedResult: AttributedString
    let error: String?

    init(
        result: String = "",
        spans: [FendSpan] = [],
        attributedResult: AttributedString? = nil,
        error: String? = nil
    ) {
        self.result = result
        self.spans = spans
        self.attributedResult = attributedResult ?? CalculatorFormatter.formatResult(spans: spans, query: nil)
        self.error = error
    }

    static func == (lhs: CalculationPreview, rhs: CalculationPreview) -> Bool {
        lhs.result == rhs.result && lhs.error == rhs.error
    }
}

/// Wraps FendContext to provide mathematical and unit conversion evaluations.
final class Calculator: @unchecked Sendable {
    static let shared = Calculator()

    private let lock = NSLock()
    private var context: FendContext?
    /// The last text asked about and its answer: two search providers ask about the same text on every keystroke.
    private var remembered: (query: String, preview: CalculationPreview?)?
    private let rememberedLock = NSLock()

    /// What day it is, which a test sets.
    let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = try? FendContext()
        self.now = now
    }

    /// Gives the calculator its exchange rates, by currency code against one base currency, or takes them away
    /// with an empty table. The answer remembered from before is forgotten: it may have been "no rates".
    func setExchangeRates(_ rates: [String: Double]) {
        lock.withLock { context?.setExchangeRates(rates) }
        rememberedLock.withLock { remembered = nil }
    }

    /// Evaluates the query for live preview in the search launcher.
    /// Returns `nil` if the query does not appear to be a calculation request or if it fails evaluation.
    /// Returns `CalculationPreview(result: "", error: ...)` for incomplete expressions, invalid unit conversions, or timeouts so the calculator block stays visible.
    func evaluatePreview(_ query: String) -> CalculationPreview? {
        let last = rememberedLock.withLock { remembered }
        if let last, last.query == query {
            return last.preview
        }
        let preview = computePreview(query)
        rememberedLock.withLock { remembered = (query, preview) }
        return preview
    }

    /// Text the patterns do not know is a calculation when it has a number in it and fend answers something else: "2 pi", "1E3".
    /// Words alone stay out, since fend reads "day one" as a day, and so does a lambda, which is how "localhost:3000" reads.
    private func isAnsweredByFend(_ typed: String) -> Bool {
        guard !typed.hasPrefix("/"), !typed.hasPrefix("~"), !typed.contains("="), !typed.contains(":") else { return false }
        guard typed.contains(where: \.isNumber), !Self.readsAsAName(typed) else { return false }
        let answer = lock.withLock { context?.preview(normalizeExpressionForEvaluation(typed)) }
        guard let answer, !answer.isEmpty else { return false }
        let spelled: (String) -> String = { $0.filter { !$0.isWhitespace }.lowercased() }
        return spelled(answer.string) != spelled(typed)
    }

    /// "4k" and "7 eleven" are sums to fend, 4000 and 77, and names to the person searching for them: a number
    /// with a k, or with nothing but numbers spelled out. "5 million" and "2 dozen" stay sums.
    private static func readsAsAName(_ typed: String) -> Bool {
        let spelled: Set = [
            "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
            "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        ]
        if typed.wholeMatch(of: /[0-9]+\s*[kK]/) != nil {
            return true
        }
        let words = typed.lowercased().split { !$0.isLetter }
        return !words.isEmpty && words.allSatisfy { spelled.contains(String($0)) } && typed.allSatisfy { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }

    /// An answer as the preview holds it: the text to copy and the text to draw, from the same spans.
    private static func shown(_ spans: [FendSpan], for query: String) -> CalculationPreview {
        CalculationPreview(
            result: formatResult(spans: spans, query: query),
            spans: spans,
            attributedResult: CalculatorFormatter.formatResult(spans: spans, query: query)
        )
    }

    private static var timedOut: CalculationPreview {
        CalculationPreview(result: "", error: String(localized: "Calculation timed out", bundle: .floe, comment: "Shown in place of a calculator result that would take too long."))
    }

    /// An empty preview that took at least this long was interrupted by fend's 200 ms limit rather
    /// than empty: the fallback is skipped, so one keystroke costs one limit and never two.
    private static let interruptedPreviewFloor: Duration = .milliseconds(150)

    private func computePreview(_ query: String) -> CalculationPreview? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Must look like a calculator query (contains operators, units, digits, base prefixes, or trailing '=')
        guard looksLikeCalculatorQuery(trimmed) || isAnsweredByFend(trimmed) else { return nil }

        var exprToEvaluate = trimmed
        if trimmed.hasSuffix("=") {
            exprToEvaluate = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !exprToEvaluate.isEmpty else { return nil }

        // Reject custom function definitions and dice rolls
        if isDiceOrCustomFunction(exprToEvaluate) {
            return nil
        }

        // Automatic non-decimal base conversion (e.g. 0x..., 0b..., 0o...)
        if isNonBaseTenNumber(exprToEvaluate) {
            return evaluateNonBaseTenToDecimal(exprToEvaluate).map { Self.shown([FendSpan(string: $0, kind: .number)], for: exprToEvaluate) }
        }

        lock.lock()
        defer { lock.unlock() }

        guard let context else { return nil }

        let normalized = normalizeExpressionForEvaluation(exprToEvaluate)

        // A factorial this large runs into fend's time limit twice, in the preview and in the fallback: say so without waiting.
        if let match = normalized.range(of: #"([0-9]+)\s*!"#, options: .regularExpression) {
            let numStr = normalized[match].replacingOccurrences(of: "!", with: "").trimmingCharacters(in: .whitespaces)
            if let n = Int(numStr), n >= 10000 {
                return Self.timedOut
            }
        }

        // Try evaluating with fend preview. A preview that comes back empty after running as long as
        // fend's own time limit (200 ms; see FendCore's TIME_LIMIT) was cut off, not empty: the
        // whole-answer fallback would pay the same limit again on the main thread and end the same way.
        let clock = ContinuousClock()
        let previewStarted = clock.now
        let res = context.preview(normalized)
        if !res.isEmpty {
            return Self.shown(res.spans, for: exprToEvaluate)
        }
        if clock.now - previewStarted >= Self.interruptedPreviewFloor {
            return Self.timedOut
        }

        // Some preview calls return empty value for valid queries (e.g. 10^50), try evaluate as fallback
        let evaluated = Result { try context.evaluate(normalized) as FendResult }
        if case let .success(evalRes) = evaluated, !evalRes.isEmpty {
            return Self.shown(evalRes.spans, for: exprToEvaluate)
        }
        // The word fend's wrapper stops an evaluation with when its time is up.
        if case .failure(FendError.evaluationFailed("interrupted")) = evaluated {
            return Self.timedOut
        }
        // And the sentence it refuses money with: it has no rates to convert by.
        if case .failure(FendError.evaluationFailed("exchange rates are not available")) = evaluated {
            return CalculationPreview(error: String(localized: "To convert money, switch on exchange rates in Settings, Privacy.", bundle: .floe, comment: "A calculator error."))
        }

        // Check if query is an invalid unit conversion
        if let unitError = unitConversionErrorMessage(exprToEvaluate, error: nil) {
            return CalculationPreview(result: "", error: unitError)
        }

        // If query is an incomplete expression (like "100 + " or "1 W to "), show empty result to keep block visible
        if isIncompleteExpression(exprToEvaluate) {
            return CalculationPreview(result: "", error: nil)
        }

        return nil
    }

    /// Normalizes mathematical symbols (like √, ∛, ∜, ×, ÷, −) into standard syntax supported by fend.
    func normalizeExpressionForEvaluation(_ query: String) -> String {
        var s = withShorthandExpanded(query)
        s = s.replacingOccurrences(of: "⁄", with: "/")
        s = s.replacingOccurrences(of: "×", with: "*")
        s = s.replacingOccurrences(of: "÷", with: "/")
        s = s.replacingOccurrences(of: "−", with: "-")
        // fend names the inverse functions asin, acos and atan; "arcsin" and the rest are the same, written out.
        s = CalculatorFormatter.replacePattern(s, pattern: #"\b[aA][rR][cC]((?i:sin|cos|tan)[hH]?)\b"#) { groups in
            "a" + groups[1].lowercased()
        }

        // ∛(x) or ∛(x or ∛x -> cbrt(x)
        s = s.replacingOccurrences(of: #"∛\(([^)]+)\)?"#, with: "cbrt($1)", options: .regularExpression)
        s = s.replacingOccurrences(of: #"∛([a-zA-Z0-9_.]+)"#, with: "cbrt($1)", options: .regularExpression)

        // ∜(x) or ∜(x or ∜x -> (x)^(1/4)
        s = s.replacingOccurrences(of: #"∜\(([^)]+)\)?"#, with: "($1)^(1/4)", options: .regularExpression)
        s = s.replacingOccurrences(of: #"∜([a-zA-Z0-9_.]+)"#, with: "($1)^(1/4)", options: .regularExpression)

        // ⁿ√x -> (x)^(1/n)
        let supToAscii = CalculatorFormatter.supToAscii
        s = CalculatorFormatter.replacePattern(s, pattern: #"([⁰¹²³⁴⁵⁶⁷⁸⁹]+)√\(([^)]+)\)?"#) { groups in
            let sup = groups[1]
            let inner = groups[2]
            let asciiDigits = String(sup.map { supToAscii[$0] ?? $0 })
            return "(\(inner))^(1/\(asciiDigits))"
        }
        s = CalculatorFormatter.replacePattern(s, pattern: #"([⁰¹²³⁴⁵⁶⁷⁸⁹]+)√([a-zA-Z0-9_.]+)"#) { groups in
            let sup = groups[1]
            let inner = groups[2]
            let asciiDigits = String(sup.map { supToAscii[$0] ?? $0 })
            return "(\(inner))^(1/\(asciiDigits))"
        }

        // √(x) or √(x or √x -> sqrt(x)
        s = s.replacingOccurrences(of: #"√\(([^)]+)\)?"#, with: "sqrt($1)", options: .regularExpression)
        s = s.replacingOccurrences(of: #"√([a-zA-Z0-9_.]+)"#, with: "sqrt($1)", options: .regularExpression)

        // A run of raised digits is one power: m² -> m^2, 13¹³ -> 13^13
        s = CalculatorFormatter.replacePattern(s, pattern: "[⁰¹²³⁴⁵⁶⁷⁸⁹]+") { groups in
            "^" + String(groups[0].map { CalculatorFormatter.supToAscii[$0] ?? $0 })
        }

        // Normalize any remaining superscripts and subscripts back to ASCII
        s = String(s.map { CalculatorFormatter.supToAscii[$0] ?? CalculatorFormatter.subToAscii[$0] ?? $0 })

        return s
    }

    /// Checks if a query is a non-base-10 literal like `0xff`, `0b1010`, `0o77`.
    func isNonBaseTenNumber(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("0x"), trimmed.count > 2 {
            let hexDigits = trimmed.dropFirst(2).filter { $0 != "_" }
            return !hexDigits.isEmpty && hexDigits.allSatisfy(\.isHexDigit)
        }
        if trimmed.hasPrefix("0b"), trimmed.count > 2 {
            let binDigits = trimmed.dropFirst(2).filter { $0 != "_" }
            return !binDigits.isEmpty && binDigits.allSatisfy { $0 == "0" || $0 == "1" }
        }
        if trimmed.hasPrefix("0o"), trimmed.count > 2 {
            let octDigits = trimmed.dropFirst(2).filter { $0 != "_" }
            return !octDigits.isEmpty && octDigits.allSatisfy { ("0" ... "7").contains($0) }
        }
        return false
    }

    /// The decimal value of a number written in another base, which fend works out however long it is.
    private func evaluateNonBaseTenToDecimal(_ query: String) -> String? {
        let literal = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let answer = lock.withLock { context?.preview("\(literal) to decimal") }
        return answer.flatMap { $0.isEmpty ? nil : $0.string }
    }
}
