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
public struct CalculationPreview: Equatable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let result: String
    public let spans: [FendSpan]
    public let attributedResult: AttributedString
    public let error: String?

    public init(
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

    public init(stringLiteral value: String) {
        self.init(result: value, spans: [], attributedResult: nil, error: nil)
    }

    public var description: String {
        result
    }

    public static func == (lhs: CalculationPreview, rhs: String) -> Bool {
        lhs.result == rhs
    }

    public static func == (lhs: String, rhs: CalculationPreview) -> Bool {
        lhs == rhs.result
    }

    public static func == (lhs: CalculationPreview, rhs: CalculationPreview) -> Bool {
        lhs.result == rhs.result && lhs.error == rhs.error
    }
}

/// Wraps FendContext to provide mathematical and unit conversion evaluations.
public final class Calculator: @unchecked Sendable {
    public static let shared = Calculator()

    private let lock = NSLock()
    private var context: FendContext?

    public init() {
        self.context = try? FendContext()
    }

    /// Evaluates the query for live preview in the search launcher.
    /// Returns `nil` if the query does not appear to be a calculation request or if it fails evaluation.
    /// Returns `CalculationPreview(result: "", error: ...)` for incomplete expressions, invalid unit conversions, or timeouts so the calculator block stays visible.
    public func evaluatePreview(_ query: String, timeoutMs: UInt64 = 500) -> CalculationPreview? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Must look like a calculator query (contains operators, units, digits, base prefixes, or trailing '=')
        guard looksLikeCalculatorQuery(trimmed) else { return nil }

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
            if let decimalResult = evaluateNonBaseTenToDecimal(exprToEvaluate) {
                let spans = [FendSpan(string: decimalResult, kind: .number)]
                let resultStr = Self.formatResult(spans: spans, query: exprToEvaluate)
                let attributed = CalculatorFormatter.formatResult(spans: spans, query: exprToEvaluate)
                return CalculationPreview(
                    result: resultStr,
                    spans: spans,
                    attributedResult: attributed,
                    error: nil
                )
            }
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        guard let context else { return nil }

        let normalized = normalizeExpressionForEvaluation(exprToEvaluate)

        if let match = normalized.range(of: #"([0-9]+)\s*!"#, options: .regularExpression) {
            let numStr = normalized[match].replacingOccurrences(of: "!", with: "").trimmingCharacters(in: .whitespaces)
            if let n = Int(numStr), n >= 10000 || timeoutMs < 50 {
                return CalculationPreview(result: "", error: String(localized: "Calculation timed out", bundle: .floe, comment: "Shown in place of a calculator result that would take too long."))
            }
        }

        // Try evaluating with fend preview
        let res = context.preview(normalized)
        if !res.isEmpty {
            let resultStr = Self.formatResult(spans: res.spans, query: exprToEvaluate)
            let attributed = CalculatorFormatter.formatResult(spans: res.spans, query: exprToEvaluate)
            return CalculationPreview(
                result: resultStr,
                spans: res.spans,
                attributedResult: attributed,
                error: nil
            )
        }

        // Some preview calls return empty value for valid queries (e.g. 10^50), try evaluate as fallback
        do {
            let evalRes = try context.evaluate(normalized)
            if !evalRes.isEmpty {
                let resultStr = Self.formatResult(spans: evalRes.spans, query: exprToEvaluate)
                let attributed = CalculatorFormatter.formatResult(spans: evalRes.spans, query: exprToEvaluate)
                return CalculationPreview(
                    result: resultStr,
                    spans: evalRes.spans,
                    attributedResult: attributed,
                    error: nil
                )
            }
        } catch {}

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
    public func normalizeExpressionForEvaluation(_ query: String) -> String {
        var s = query
        s = s.replacingOccurrences(of: "⁄", with: "/")
        s = s.replacingOccurrences(of: "×", with: "*")
        s = s.replacingOccurrences(of: "÷", with: "/")
        s = s.replacingOccurrences(of: "−", with: "-")

        // ∛(x) or ∛(x or ∛x -> cbrt(x)
        s = s.replacingOccurrences(of: #"∛\(([^)]+)\)?"#, with: "cbrt($1)", options: .regularExpression)
        s = s.replacingOccurrences(of: #"∛([a-zA-Z0-9_.]+)"#, with: "cbrt($1)", options: .regularExpression)

        // ∜(x) or ∜(x or ∜x -> (x)^(1/4)
        s = s.replacingOccurrences(of: #"∜\(([^)]+)\)?"#, with: "($1)^(1/4)", options: .regularExpression)
        s = s.replacingOccurrences(of: #"∜([a-zA-Z0-9_.]+)"#, with: "($1)^(1/4)", options: .regularExpression)

        // ⁿ√x -> (x)^(1/n)
        let supToAscii: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
            "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
            "ⁿ": "n",
        ]
        s = CalculatorFormatter.replacePattern(s, pattern: #"([⁰¹²³⁴⁵⁶⁷⁸⁹]+)√\(([^)]+)\)?"#) { match, full in
            let sup = (full as NSString).substring(with: match.range(at: 1))
            let inner = (full as NSString).substring(with: match.range(at: 2))
            let asciiDigits = String(sup.map { supToAscii[$0] ?? $0 })
            return "(\(inner))^(1/\(asciiDigits))"
        }
        s = CalculatorFormatter.replacePattern(s, pattern: #"([⁰¹²³⁴⁵⁶⁷⁸⁹]+)√([a-zA-Z0-9_.]+)"#) { match, full in
            let sup = (full as NSString).substring(with: match.range(at: 1))
            let inner = (full as NSString).substring(with: match.range(at: 2))
            let asciiDigits = String(sup.map { supToAscii[$0] ?? $0 })
            return "(\(inner))^(1/\(asciiDigits))"
        }

        // √(x) or √(x or √x -> sqrt(x)
        s = s.replacingOccurrences(of: #"√\(([^)]+)\)?"#, with: "sqrt($1)", options: .regularExpression)
        s = s.replacingOccurrences(of: #"√([a-zA-Z0-9_.]+)"#, with: "sqrt($1)", options: .regularExpression)

        // Normalize unit powers like m² -> m^2
        s = s.replacingOccurrences(of: "²", with: "^2")
        s = s.replacingOccurrences(of: "³", with: "^3")
        s = s.replacingOccurrences(of: "⁴", with: "^4")

        // Normalize any remaining superscripts and subscripts back to ASCII
        s = String(s.map { CalculatorFormatter.supToAscii[$0] ?? CalculatorFormatter.subToAscii[$0] ?? $0 })

        return s
    }

    /// Checks if a query is a non-base-10 literal like `0xff`, `0b1010`, `0o77`.
    public func isNonBaseTenNumber(_ query: String) -> Bool {
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

    /// Converts an arbitrary-precision non-negative integer string in a given radix (2, 8, 16) to a decimal string representation.
    public static func convertRadixToDecimalString(_ digits: String, radix: Int) -> String? {
        let clean = digits.filter { $0 != "_" }
        guard !clean.isEmpty else { return nil }
        var resultDigits = [0]
        for ch in clean {
            guard let val = ch.hexDigitValue, val < radix else { return nil }
            var carry = val
            for i in 0 ..< resultDigits.count {
                let product = resultDigits[i] * radix + carry
                resultDigits[i] = product % 10
                carry = product / 10
            }
            while carry > 0 {
                resultDigits.append(carry % 10)
                carry /= 10
            }
        }
        return resultDigits.reversed().map(String.init).joined()
    }

    /// Converts a non-base-10 literal to its decimal string representation.
    private func evaluateNonBaseTenToDecimal(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("0x") {
            let hex = String(trimmed.dropFirst(2))
            return Self.convertRadixToDecimalString(hex, radix: 16)
        } else if trimmed.hasPrefix("0b") {
            let bin = String(trimmed.dropFirst(2))
            return Self.convertRadixToDecimalString(bin, radix: 2)
        } else if trimmed.hasPrefix("0o") {
            let oct = String(trimmed.dropFirst(2))
            return Self.convertRadixToDecimalString(oct, radix: 8)
        }
        return nil
    }
}
