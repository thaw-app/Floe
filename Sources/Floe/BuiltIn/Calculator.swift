//
//  Calculator.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import FendCore
import AppKit
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
            if let n = Int(numStr), (n >= 10000 || timeoutMs < 50) {
                return CalculationPreview(result: "", error: "Calculation timed out")
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
        } catch {
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
            "ⁿ": "n"
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
        if trimmed.hasPrefix("0x") && trimmed.count > 2 {
            let hexDigits = trimmed.dropFirst(2).filter { $0 != "_" }
            return !hexDigits.isEmpty && hexDigits.allSatisfy { $0.isHexDigit }
        }
        if trimmed.hasPrefix("0b") && trimmed.count > 2 {
            let binDigits = trimmed.dropFirst(2).filter { $0 != "_" }
            return !binDigits.isEmpty && binDigits.allSatisfy { $0 == "0" || $0 == "1" }
        }
        if trimmed.hasPrefix("0o") && trimmed.count > 2 {
            let octDigits = trimmed.dropFirst(2).filter { $0 != "_" }
            return !octDigits.isEmpty && octDigits.allSatisfy { ("0"..."7").contains($0) }
        }
        return false
    }

    /// Converts an arbitrary-precision non-negative integer string in a given radix (2, 8, 16) to a decimal string representation.
    public static func convertRadixToDecimalString(_ digits: String, radix: Int) -> String? {
        let clean = digits.filter { $0 != "_" }
        guard !clean.isEmpty else { return nil }
        var resultDigits: [Int] = [0]
        for ch in clean {
            guard let val = ch.hexDigitValue, val < radix else { return nil }
            var carry = val
            for i in 0..<resultDigits.count {
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

    /// Determines if a query should activate the calculator UI.
    private func looksLikeCalculatorQuery(_ query: String) -> Bool {
        let lower = query.lowercased()

        // Paths starting with / or ~ are file locations, not calculations
        if query.hasPrefix("/") || query.hasPrefix("~") {
            return false
        }

        // Trailing '=' forces calculator activation: {expr} =
        if query.hasSuffix("=") {
            let expr = String(query.dropLast()).trimmingCharacters(in: .whitespaces)
            // Reject if the expression itself contains '=' (no variable declarations or repeated '=')
            if expr.contains("=") {
                return false
            }
            return !expr.isEmpty
        }

        // If the query contains '=' anywhere else, reject it (no variable declarations like a=123)
        if query.contains("=") {
            return false
        }

        // Factorial expressions: e.g. 5!, 100!, 10000000!
        if lower.range(of: #"[0-9]+\s*!"#, options: .regularExpression) != nil {
            return true
        }

        // Explicit non-base-10 numbers with digits (e.g. 0xff, 0b101, 0o77)
        if isNonBaseTenNumber(lower) {
            return true
        }

        // Do not activate on just "0x", "0b", "0o" without digits
        if lower == "0x" || lower == "0b" || lower == "0o" {
            return false
        }

        // Common math constants or functions
        let mathPrefixes = [
            "pi", "tau", "e", "sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan",
            "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "ln", "log", "log2", "log10",
            "abs", "floor", "ceil", "round"
        ]
        for prefix in mathPrefixes {
            if lower == prefix || lower.hasPrefix(prefix + "(") || lower.hasPrefix(prefix + " ") {
                return true
            }
        }

        // Check for conversion keywords like "to", "in", "as"
        let conversionPatterns = [
            #"\bto\b"#,
            #"\bin\b"#,
            #"\binto\b"#,
            #"\bas\b"#
        ]
        for pattern in conversionPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                // Must have some number or unit expression
                return true
            }
        }

        // Query ending with conversion keyword like "10 W to" or "10W to "
        if lower.range(of: #"\b(to|in|into|as)\s*$"#, options: .regularExpression) != nil {
            return true
        }

        // Contains mathematical operators (+, -, *, /, ^, %, √, ∛, ∜, sqrt, cbrt)
        let hasOperator = query.contains("+") ||
            query.contains("-") ||
            query.contains("−") ||
            query.contains("*") ||
            query.contains("×") ||
            query.contains("/") ||
            query.contains("÷") ||
            query.contains("⁄") ||
            query.contains("^") ||
            query.contains("%") ||
            query.contains("√") ||
            query.contains("∛") ||
            query.contains("∜") ||
            query.contains("sqrt") ||
            query.contains("cbrt")

        if hasOperator {
            // Must contain at least one digit or identifier
            return query.contains(where: { $0.isNumber || $0.isLetter })
        }

        return false
    }

    /// Known common units to avoid activating calculator on arbitrary text.
    private func isRecognizedUnit(_ unit: String) -> Bool {
        let units: Set<String> = [
            // Power & Energy
            "w", "kw", "mw", "gw", "hp", "j", "kj", "mj", "gj", "cal", "kcal", "wh", "kwh", "mwh", "ev", "btu",
            // Mass & Weight
            "g", "kg", "mg", "ug", "µg", "lb", "lbs", "oz", "t", "ton", "tons", "tonne", "tonnes", "st", "stone",
            // Length & Distance
            "m", "km", "cm", "mm", "um", "µm", "nm", "pm", "mi", "mile", "miles", "yd", "yard", "yards", "ft", "foot", "feet", "in", "inch", "inches",
            // Area & Volume
            "sqm", "sqft", "acre", "acres", "ha", "hectare", "hectares", "l", "ml", "cl", "dl", "gal", "gallon", "gallons", "qt", "pt", "cup", "cups", "tbsp", "tsp", "floz",
            // Time
            "s", "sec", "second", "seconds", "min", "minute", "minutes", "h", "hr", "hour", "hours", "d", "day", "days", "wk", "week", "weeks", "yr", "year", "years", "ms", "us", "ns",
            // Temperature
            "c", "f", "k", "celsius", "fahrenheit", "kelvin", "°c", "°f",
            // Speed & Pressure
            "kph", "kmh", "mph", "mps", "knot", "knots", "pa", "kpa", "mpa", "bar", "mbar", "psi", "atm", "torr",
            // Digital
            "b", "kb", "mb", "gb", "tb", "pb", "kib", "mib", "gib", "tib", "bit", "kbit", "mbit", "gbit", "byte", "bytes",
            // Electricity & Waves
            "v", "kv", "mv", "a", "ma", "ka", "ohm", "ohms", "hz", "khz", "mhz", "ghz", "rad", "deg"
        ]
        return units.contains(unit.lowercased())
    }

    /// Checks if expression is incomplete and awaiting more input.
    private func isIncompleteExpression(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Ends with an operator
        let operatorEndings = ["+", "-", "−", "*", "×", "/", "÷", "⁄", "^", "%", "(", ",", "√", "∛", "∜"]
        for op in operatorEndings {
            if trimmed.hasSuffix(op) {
                return true
            }
        }

        // Unclosed parentheses awaiting more input
        var parenDepth = 0
        for ch in trimmed {
            if ch == "(" { parenDepth += 1 }
            else if ch == ")" { parenDepth = max(0, parenDepth - 1) }
        }
        if parenDepth > 0 {
            return true
        }

        // Ends with conversion keyword: "to", "in", "as", "into"
        let conversionEndings = [
            #"\bto$"#,
            #"\bin$"#,
            #"\binto$"#,
            #"\bas$"#
        ]
        for pattern in conversionEndings {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    /// Generates a friendly error message when a unit conversion fails (e.g. "Cannot convert Power to Temperature.").
    private func unitConversionErrorMessage(_ query: String, error: Error? = nil) -> String? {
        let lower = query.lowercased()
        guard let toRange = lower.range(of: #"\b(to|in|into|as)\b"#, options: .regularExpression) else {
            return nil
        }

        let leftPart = String(lower[..<toRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rightPart = String(lower[toRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !leftPart.isEmpty, !rightPart.isEmpty else { return nil }

        let fromCategory = unitCategory(leftPart)
        let toCategory = unitCategory(rightPart)

        if let from = fromCategory, let to = toCategory, from != to {
            return "Cannot convert \(from) to \(to)."
        }

        if let from = fromCategory, toCategory == nil {
            return "Cannot convert \(from) to '\(rightPart)'."
        }

        if let errDesc = error?.localizedDescription, !errDesc.isEmpty && !errDesc.contains("expected") {
            return errDesc
        }

        return "Incompatible unit conversion."
    }

    /// Determines the dimensional category of a unit string.
    private func unitCategory(_ text: String) -> String? {
        let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
        let unitStr: String
        if let match = lower.range(of: #"[a-zA-Z°µΩ]+$"#, options: .regularExpression) {
            unitStr = String(lower[match])
        } else {
            unitStr = lower
        }

        switch unitStr {
        case "w", "kw", "mw", "gw", "hp":
            return "Power"
        case "j", "kj", "mj", "gj", "cal", "kcal", "wh", "kwh", "mwh", "ev", "btu":
            return "Energy"
        case "g", "kg", "mg", "ug", "µg", "lb", "lbs", "oz", "t", "ton", "tons", "tonne", "tonnes", "st", "stone":
            return "Mass"
        case "m", "km", "cm", "mm", "um", "µm", "nm", "pm", "mi", "mile", "miles", "yd", "yard", "yards", "ft", "foot", "feet", "in", "inch", "inches":
            return "Length"
        case "sqm", "sqft", "acre", "acres", "ha", "hectare", "hectares":
            return "Area"
        case "l", "ml", "cl", "dl", "gal", "gallon", "gallons", "qt", "pt", "cup", "cups", "tbsp", "tsp", "floz":
            return "Volume"
        case "s", "sec", "second", "seconds", "min", "minute", "minutes", "h", "hr", "hour", "hours", "d", "day", "days", "wk", "week", "weeks", "yr", "year", "years", "ms", "us", "ns":
            return "Time"
        case "c", "f", "k", "celsius", "fahrenheit", "kelvin", "°c", "°f":
            return "Temperature"
        case "kph", "kmh", "mph", "mps", "knot", "knots", "km/h", "km⁄h", "m/s", "m⁄s", "mi/h", "mi⁄h", "ft/s", "ft⁄s":
            return "Speed"
        case "pa", "kpa", "mpa", "bar", "mbar", "psi", "atm", "torr":
            return "Pressure"
        case "b", "kb", "mb", "gb", "tb", "pb", "kib", "mib", "gib", "tib", "bit", "kbit", "mbit", "gbit", "byte", "bytes":
            return "Digital Storage"
        case "v", "kv", "mv":
            return "Voltage"
        case "a", "ma", "ka":
            return "Current"
        case "ohm", "ohms":
            return "Resistance"
        case "hz", "khz", "mhz", "ghz":
            return "Frequency"
        default:
            return nil
        }
    }

    /// Rejects dice rolls (e.g. `d6`, `2d20`, `roll`) and custom function definitions (`x: x + 1`, `f = ...`).
    private func isDiceOrCustomFunction(_ query: String) -> Bool {
        let lower = query.lowercased()

        // Dice patterns: standalone d6, 2d20, roll d6, etc.
        if lower.range(of: #"\b(\d*)d(\d+)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\broll\b"#, options: .regularExpression) != nil {
            return true
        }

        // Custom function patterns: `x: x + 1` or `f = x: x^2`
        if lower.range(of: #"[a-zA-Z_]\s*:\s*[a-zA-Z_]"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    /// Formats the result using FendResult.
    public static func formatResult(_ result: FendResult, query: String? = nil) -> String {
        formatResult(spans: result.spans, query: query)
    }

    /// Formats the result from syntactic spans produced by FendCore.
    /// Replaces approximation spans with `≈` and limits precision to 16 digits, switching to scientific notation if exceeded.
    /// If the query requested a conversion to a non-decimal base, appends the base in subscript.
    public static func formatResult(spans: [FendSpan], query: String? = nil) -> String {
        guard !spans.isEmpty else { return "" }

        var hasApprox = false
        var targetBase = query.flatMap { CalculatorFormatter.targetBase(from: $0) }

        // Filter out approximation spans
        var contentSpans: [FendSpan] = []
        for span in spans {
            let str = span.string
            if str.hasPrefix("approx. ") || str.hasPrefix("approx.") || str.hasPrefix("≈ ") || str.hasPrefix("≈") {
                hasApprox = true
            } else {
                contentSpans.append(span)
            }
        }

        guard !contentSpans.isEmpty else { return "" }

        // If a non-decimal target base was requested in the query, or if the value itself has a non-decimal base prefix, format as non-decimal base
        if targetBase == nil || targetBase == 10 {
            if let firstNum = contentSpans.first(where: { $0.kind == .number }) {
                let s = firstNum.string
                if s.hasPrefix("0x") || s.hasPrefix("0X") {
                    targetBase = 16
                } else if s.hasPrefix("0b") || s.hasPrefix("0B") {
                    targetBase = 2
                } else if s.hasPrefix("0o") || s.hasPrefix("0O") {
                    targetBase = 8
                }
            }
        }

        if let base = targetBase, base != 10 {
            let baseSubscript = CalculatorFormatter.toSubscript("\(base)")
            guard let numIndex = contentSpans.firstIndex(where: { $0.kind == .number }) else {
                let raw = contentSpans.map(\.string).joined()
                let prefix = hasApprox ? "≈ " : ""
                return "\(prefix)\(raw)"
            }

            var digits = contentSpans[numIndex].string.trimmingCharacters(in: .whitespaces)
            var sign = ""
            if digits.hasPrefix("-") || digits.hasPrefix("−") {
                sign = "−"
                digits = String(digits.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if digits.hasSuffix(baseSubscript) {
                digits = String(digits.dropLast(baseSubscript.count)).trimmingCharacters(in: .whitespaces)
            }
            if digits.hasPrefix("0x") || digits.hasPrefix("0X") ||
               digits.hasPrefix("0b") || digits.hasPrefix("0B") ||
               digits.hasPrefix("0o") || digits.hasPrefix("0O") {
                digits = String(digits.dropFirst(2))
            }

            let (formatted, wasRounded) = formatBaseNumber(digits, base: base, maxDigits: 16, sciNotDigits: 10)
            if wasRounded {
                hasApprox = true
            }

            // Format remaining spans (such as units)
            var restFormatted = ""
            var needsLeadingSpace = true
            for (idx, span) in contentSpans.enumerated() {
                guard idx != numIndex else { continue }
                switch span.kind {
                case .identifier:
                    var unitStr = span.string
                    unitStr = unitStr.replacingOccurrences(of: " / ", with: "/")
                    unitStr = CalculatorFormatter.formatUnitFractions(unitStr)
                    let trimmed = unitStr.trimmingCharacters(in: .whitespaces)
                    let hasLeadingSpace = unitStr.hasPrefix(" ")
                    let cased = (hasLeadingSpace ? " " : "") + CalculatorFormatter.normalizeUnitString(trimmed)
                    if needsLeadingSpace && !cased.hasPrefix(" ") {
                        restFormatted += " "
                    }
                    restFormatted += cased
                    needsLeadingSpace = cased.hasSuffix(" ")
                case .whitespace:
                    restFormatted += span.string
                    needsLeadingSpace = false
                case .other:
                    var sym = span.string
                    if sym == "*" { sym = " × " }
                    else if sym == "/" { sym = " ÷ " }
                    else if sym == "-" { sym = " − " }
                    restFormatted += sym
                    needsLeadingSpace = sym.hasSuffix(" ")
                default:
                    restFormatted += span.string
                    needsLeadingSpace = span.string.hasSuffix(" ")
                }
            }

            let prefix = hasApprox ? "≈ " : ""
            return "\(prefix)\(sign)\(formatted)\(restFormatted)"
        }

        var formattedParts: [String] = []
        for span in contentSpans {
            switch span.kind {
            case .number:
                let (formatted, truncated) = formatNumber(span.string, maxDigits: 16, sciNotDigits: 10)
                if truncated {
                    hasApprox = true
                }
                formattedParts.append(formatted)
            case .identifier:
                var unitStr = span.string
                unitStr = unitStr.replacingOccurrences(of: " / ", with: "/")
                unitStr = CalculatorFormatter.formatUnitFractions(unitStr)
                let trimmed = unitStr.trimmingCharacters(in: .whitespaces)
                let hasLeadingSpace = unitStr.hasPrefix(" ")
                let cased = (hasLeadingSpace ? " " : "") + CalculatorFormatter.normalizeUnitString(trimmed)
                formattedParts.append(cased)
            default:
                formattedParts.append(span.string)
            }
        }

        let prefix = hasApprox ? "≈ " : ""
        return "\(prefix)\(formattedParts.joined())"
    }

    /// Formats the raw result string from fend.
    /// Converts to spans and delegates to `formatResult(spans:query:)`.
    public static func formatResult(_ value: String, query: String? = nil) -> String {
        var s = value
        var hasApprox = false
        if s.hasPrefix("approx. ") {
            hasApprox = true
            s = String(s.dropFirst(8))
        } else if s.hasPrefix("approx.") {
            hasApprox = true
            s = String(s.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("≈ ") {
            hasApprox = true
            s = String(s.dropFirst(2))
        } else if s.hasPrefix("≈") {
            hasApprox = true
            s = String(s.dropFirst(1)).trimmingCharacters(in: .whitespaces)
        }

        // Try getting spans from Fend preview
        let preview = Fend.preview(s)
        if !preview.spans.isEmpty {
            var spans = preview.spans
            if hasApprox {
                spans.insert(FendSpan(string: "approx. ", kind: .identifier), at: 0)
            }
            return formatResult(spans: spans, query: query)
        }

        // If s has a number and unit split by regex as fallback:
        if let match = s.range(of: #"^([+-]?[0-9a-fA-F_]+(?:[\u2080-\u2089]+)?(?:\.[0-9a-fA-F_]+)?(?:[eE][+-]?[0-9]+)?)\s*(.*)$"#, options: .regularExpression) {
            let matched = String(s[match])
            if let numRange = matched.range(of: #"^[+-]?[0-9a-fA-F_]+(?:[\u2080-\u2089]+)?(?:\.[0-9a-fA-F_]+)?(?:[eE][+-]?[0-9]+)?"#, options: .regularExpression) {
                let numStr = String(matched[numRange])
                let rest = String(matched[numRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                var spans: [FendSpan] = []
                if hasApprox {
                    spans.append(FendSpan(string: "approx. ", kind: .identifier))
                }
                spans.append(FendSpan(string: numStr, kind: .number))
                if !rest.isEmpty {
                    spans.append(FendSpan(string: " \(rest)", kind: .identifier))
                }
                return formatResult(spans: spans, query: query)
            }
        }

        let spans = [
            hasApprox ? FendSpan(string: "approx. ", kind: .identifier) : nil,
            FendSpan(string: s, kind: .number)
        ].compactMap { $0 }
        return formatResult(spans: spans, query: query)
    }

    /// Formats an arbitrary decimal string to at most `maxDigits` significant digits, switching to scientific notation if needed.
    public static func formatNumber(_ numStr: String, maxDigits: Int = 16, sciNotDigits: Int = 10) -> (String, Bool) {
        var str = numStr
        var sign = ""
        if str.hasPrefix("-") {
            sign = "-"
            str = String(str.dropFirst())
        } else if str.hasPrefix("+") {
            str = String(str.dropFirst())
        }

        // Check for existing scientific notation
        if let eIndex = str.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let mantissaStr = String(str[..<eIndex])
            let expStr = String(str[str.index(after: eIndex)...])
            let (formattedMantissa, mantissaRounded) = formatNumber(mantissaStr, maxDigits: sciNotDigits, sciNotDigits: sciNotDigits)
            return ("\(sign)\(formattedMantissa)e\(expStr)", mantissaRounded)
        }

        let parts = str.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = String(parts[0])
        let fracPart = parts.count > 1 ? String(parts[1]) : nil

        let intDigitsCount = (intPart == "0") ? 0 : intPart.count

        if intDigitsCount > maxDigits {
            // Integer exceeds maxDigits -> switch to scientific notation
            let allDigits = intPart + (fracPart ?? "")
            var rounded = roundDigits(allDigits, precision: sciNotDigits)
            var exp = intDigitsCount - 1
            if rounded.count > sciNotDigits {
                exp += 1
                rounded = String(rounded.prefix(sciNotDigits))
            }
            let first = rounded.prefix(1)
            let rest = String(rounded.dropFirst().reversed().drop(while: { $0 == "0" }).reversed())
            let mantissa = rest.isEmpty ? "\(first)" : "\(first).\(rest)"
            let dropped = allDigits.count > sciNotDigits ? allDigits.dropFirst(sciNotDigits) : ""
            let wasRounded = !dropped.isEmpty && !dropped.allSatisfy({ $0 == "0" }) || rounded.count > allDigits.prefix(sciNotDigits).count
            return ("\(sign)\(mantissa)e+\(exp)", wasRounded)
        } else if intDigitsCount > 0 {
            // Integer is <= maxDigits
            if let fracPart {
                let allowedFrac = max(0, maxDigits - intDigitsCount)
                if allowedFrac == 0 {
                    let wasRounded = !fracPart.allSatisfy({ $0 == "0" })
                    return ("\(sign)\(intPart)", wasRounded)
                }
                if fracPart.count > allowedFrac {
                    let combined = intPart + fracPart
                    let rounded = roundDigits(combined, precision: maxDigits)
                    if rounded.count > combined.prefix(maxDigits).count {
                        return ("\(sign)\(rounded)e+\(intDigitsCount)", true)
                    }
                    let newInt = String(rounded.prefix(intDigitsCount))
                    let newFracRaw = String(rounded.dropFirst(intDigitsCount))
                    let newFrac = String(newFracRaw.reversed().drop(while: { $0 == "0" }).reversed())
                    let dropped = combined.dropFirst(maxDigits)
                    let wasRounded = !dropped.isEmpty && !dropped.allSatisfy({ $0 == "0" })
                    return (newFrac.isEmpty ? "\(sign)\(newInt)" : "\(sign)\(newInt).\(newFrac)", wasRounded)
                } else {
                    return ("\(sign)\(intPart).\(fracPart)", false)
                }
            } else {
                return ("\(sign)\(intPart)", false)
            }
        } else {
            // Zero integer part, e.g. "0.000123"
            guard let fracPart else { return ("\(sign)0", false) }
            let leadingZeros = fracPart.prefix(while: { $0 == "0" }).count
            let sigFrac = String(fracPart.dropFirst(leadingZeros))
            if sigFrac.isEmpty {
                return ("0", false)
            }
            var exp = -(leadingZeros + 1)
            if (leadingZeros + 1) > maxDigits {
                var rounded = roundDigits(sigFrac, precision: sciNotDigits)
                if rounded.count > sciNotDigits {
                    exp += 1
                    rounded = String(rounded.prefix(sciNotDigits))
                }
                let first = rounded.prefix(1)
                let rest = String(rounded.dropFirst().reversed().drop(while: { $0 == "0" }).reversed())
                let mantissa = rest.isEmpty ? "\(first)" : "\(first).\(rest)"
                let dropped = sigFrac.count > sciNotDigits ? sigFrac.dropFirst(sciNotDigits) : ""
                let wasRounded = !dropped.isEmpty && !dropped.allSatisfy({ $0 == "0" }) || rounded.count > sigFrac.prefix(sciNotDigits).count
                return ("\(sign)\(mantissa)e\(exp)", wasRounded)
            } else {
                if sigFrac.count > maxDigits {
                    let rounded = roundDigits(sigFrac, precision: sciNotDigits)
                    if rounded.count > sciNotDigits {
                        if leadingZeros == 0 {
                            return ("\(sign)1", true)
                        } else {
                            let newLeading = leadingZeros - 1
                            let fracRaw = String(repeating: "0", count: newLeading) + String(rounded.prefix(sciNotDigits))
                            let fracRes = String(fracRaw.reversed().drop(while: { $0 == "0" }).reversed())
                            return ("\(sign)0.\(fracRes)", true)
                        }
                    } else {
                        let fracRaw = String(repeating: "0", count: leadingZeros) + rounded
                        let fracRes = String(fracRaw.reversed().drop(while: { $0 == "0" }).reversed())
                        return ("\(sign)0.\(fracRes)", true)
                    }
                } else {
                    return ("\(sign)0.\(fracPart)", false)
                }
            }
        }
    }

    /// Value of a digit character in base up to 36.
    private static func digitValue(_ c: Character) -> Int? {
        if let v = c.wholeNumberValue { return v }
        if let ascii = c.asciiValue {
            if ascii >= 65 && ascii <= 90 { return Int(ascii - 65 + 10) }
            if ascii >= 97 && ascii <= 122 { return Int(ascii - 97 + 10) }
        }
        return nil
    }

    /// Converts an integer value 0..<36 to a digit character.
    private static func valueToDigit(_ v: Int, uppercase: Bool = true) -> Character {
        if v < 10 { return Character("\(v)") }
        let ascii: UInt8 = uppercase ? (65 + UInt8(v - 10)) : (97 + UInt8(v - 10))
        return Character(UnicodeScalar(ascii))
    }

    /// Formats a number string in an arbitrary base (e.g. 2, 8, 16) into scientific notation if its integer digits exceed `maxDigits`.
    /// In scientific notation, only up to `sciNotDigits` (10) digits are shown, formatted as `mantissa₍base₎ × baseⁿ`.
    public static func formatBaseNumber(
        _ rawDigits: String,
        base: Int,
        maxDigits: Int = 16,
        sciNotDigits: Int = 10
    ) -> (String, Bool) {
        let clean = rawDigits.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return ("", false) }

        var sign = ""
        var str = clean
        if str.hasPrefix("-") || str.hasPrefix("−") {
            sign = "−"
            str = String(str.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if str.hasPrefix("+") {
            str = String(str.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let baseSubscript = CalculatorFormatter.toSubscript("\(base)")

        // Strip existing base subscript if present
        if str.hasSuffix(baseSubscript) {
            str = String(str.dropLast(baseSubscript.count)).trimmingCharacters(in: .whitespaces)
        }

        str = str.filter { $0 != "_" }

        let parts = str.split(separator: ".", omittingEmptySubsequences: false)
        var intPart = String(parts[0])
        var fracPart = parts.count > 1 ? String(parts[1]) : nil

        if base == 16 {
            intPart = intPart.uppercased()
            fracPart = fracPart?.uppercased()
        }

        let intDigitsCount = (intPart == "0") ? 0 : intPart.count

        guard intDigitsCount > maxDigits else {
            let fracStr = fracPart != nil ? ".\(fracPart!)" : ""
            let combined = "\(intPart)\(fracStr)"
            return ("\(sign)\(combined)\(baseSubscript)", false)
        }

        let allDigitsStr = intPart + (fracPart ?? "")
        let allChars = Array(allDigitsStr)

        let precision = min(sciNotDigits, allChars.count)
        var mantissaDigits = Array(allChars.prefix(precision)).compactMap { digitValue($0) }
        guard !mantissaDigits.isEmpty else { return ("\(sign)0\(baseSubscript)", false) }

        var exp = intDigitsCount - 1
        var wasRounded = false

        if allChars.count > precision {
            let nextChar = allChars[precision]
            let nextVal = digitValue(nextChar) ?? 0
            let threshold = (base + 1) / 2

            let dropped = allChars[precision...]
            if dropped.contains(where: { (digitValue($0) ?? 0) != 0 }) {
                wasRounded = true
            }

            if nextVal >= threshold {
                wasRounded = true
                var carry = 1
                for i in stride(from: mantissaDigits.count - 1, through: 0, by: -1) {
                    let sum = mantissaDigits[i] + carry
                    if sum >= base {
                        mantissaDigits[i] = sum - base
                        carry = 1
                    } else {
                        mantissaDigits[i] = sum
                        carry = 0
                        break
                    }
                }
                if carry > 0 {
                    mantissaDigits.insert(carry, at: 0)
                    exp += 1
                    if mantissaDigits.count > sciNotDigits {
                        mantissaDigits = Array(mantissaDigits.prefix(sciNotDigits))
                    }
                }
            }
        }

        let first = String(valueToDigit(mantissaDigits[0]))
        var restDigits = Array(mantissaDigits.dropFirst())
        while let last = restDigits.last, last == 0 {
            restDigits.removeLast()
        }
        let rest = String(restDigits.map { valueToDigit($0) })
        let mantissa = rest.isEmpty ? first : "\(first).\(rest)"

        let supExp = CalculatorFormatter.toSuperscript("\(exp)")
        let formatted: String
        if base == 10 {
            if mantissa == "1" {
                formatted = "10\(supExp)"
            } else {
                formatted = "\(mantissa) × 10\(supExp)"
            }
        } else {
            formatted = "\(mantissa)\(baseSubscript) × \(base)\(supExp)"
        }

        return ("\(sign)\(formatted)", wasRounded)
    }

    /// Rounds a sequence of numeric characters to `precision` significant digits using half-up rounding.
    private static func roundDigits(_ digits: String, precision: Int) -> String {
        guard digits.count > precision else { return digits }
        let take = Array(digits.prefix(precision))
        let nextChar = digits[digits.index(digits.startIndex, offsetBy: precision)]
        guard let nextDigit = nextChar.wholeNumberValue, nextDigit >= 5 else {
            return String(take)
        }
        var arr = take.compactMap { $0.wholeNumberValue }
        var carry = 1
        for i in stride(from: arr.count - 1, through: 0, by: -1) {
            let sum = arr[i] + carry
            arr[i] = sum % 10
            carry = sum / 10
        }
        if carry > 0 {
            arr.insert(carry, at: 0)
        }
        return arr.map(String.init).joined()
    }
}

// MARK: - Calculator Formatter

/// Rich text formatter for calculator user inputs and outputs.
public enum CalculatorFormatter {
    private static let supMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        ".": "˙", "·": "˙", "/": "ᐟ", "⁄": "ᐟ",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ",
        "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
        "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ",
        "p": "ᵖ", "q": "𐞥", "r": "ʳ", "s": "ˢ", "t": "ᵗ",
        "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "A": "ᴬ", "B": "ᴮ", "C": "ᶜ", "D": "ᴰ", "E": "ᴱ",
        "G": "ᴳ", "H": "ᴴ", "I": "ᴵ", "J": "ᴶ", "K": "ᴷ",
        "L": "ᴸ", "M": "ᴹ", "N": "ᴺ", "O": "ᴼ", "P": "ᴾ",
        "R": "ᴿ", "T": "ᵀ", "U": "ᵁ", "V": "ⱽ", "W": "ᵂ"
    ]

    private static let fendContext = try? FendContext()

    private static let subMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
        "v": "ᵥ", "x": "ₓ"
    ]

    public static let supToAscii: [Character: Character] = {
        var map = [Character: Character]()
        for (k, v) in supMap {
            map[v] = k
        }
        return map
    }()

    public static let subToAscii: [Character: Character] = {
        var map = [Character: Character]()
        for (k, v) in subMap {
            map[v] = k
        }
        return map
    }()

    /// Known common units to format compound unit fractions.
    public static func isRecognizedUnit(_ unit: String) -> Bool {
        let stripped = unit.replacingOccurrences(of: #"[⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻ⁿ]+"#, with: "", options: .regularExpression)
        let lower = stripped.lowercased()
        let units: Set<String> = [
            // Power & Energy
            "w", "kw", "mw", "gw", "hp", "j", "kj", "mj", "gj", "cal", "kcal", "wh", "kwh", "mwh", "ev", "btu", "n",
            // Mass & Weight
            "g", "kg", "mg", "ug", "µg", "lb", "lbs", "oz", "t", "ton", "tons", "tonne", "tonnes", "st", "stone",
            // Length & Distance
            "m", "km", "cm", "mm", "um", "µm", "nm", "pm", "mi", "mile", "miles", "yd", "yard", "yards", "ft", "foot", "feet", "in", "inch", "inches",
            // Area & Volume
            "sqm", "sqft", "acre", "acres", "ha", "hectare", "hectares", "l", "ml", "cl", "dl", "gal", "gallon", "gallons", "qt", "pt", "cup", "cups", "tbsp", "tsp", "floz",
            // Time
            "s", "sec", "second", "seconds", "min", "minute", "minutes", "h", "hr", "hour", "hours", "d", "day", "days", "wk", "week", "weeks", "yr", "year", "years", "ms", "us", "ns",
            // Temperature
            "c", "f", "k", "celsius", "fahrenheit", "kelvin", "°c", "°f",
            // Speed & Pressure
            "kph", "kmh", "mph", "mps", "knot", "knots", "pa", "kpa", "mpa", "bar", "mbar", "psi", "atm", "torr",
            // Digital
            "b", "kb", "mb", "gb", "tb", "pb", "kib", "mib", "gib", "tib", "pib", "eib", "zib", "yib", "bit", "bits", "kbit", "mbit", "gbit", "byte", "bytes",
            "kibibit", "mebibit", "gibibit", "tebibit", "pebibit", "exbibit", "zebibit", "yobibit",
            "kibibits", "mebibits", "gibibits", "tebibits", "pebibits", "exbibits", "zebibits", "yobibits",
            "kibibyte", "mebibyte", "gibibyte", "tebibyte", "pebibyte", "exbibyte", "zebibyte", "yobibyte",
            "kibibytes", "mebibytes", "gibibytes", "tebibytes", "pebibytes", "exbibytes", "zebibytes", "yobibytes",
            // Electricity & Waves
            "v", "kv", "mv", "a", "ma", "ka", "ohm", "ohms", "hz", "khz", "mhz", "ghz", "rad", "deg", "mol", "cd"
        ]
        return units.contains(lower) || unitCasing[lower] != nil || bibitUnits[lower] != nil
    }

    /// Formats compound units with division signs to render with a slash `/` without spaces instead of a division symbol `÷`.
    public static func formatUnitFractions(_ text: String) -> String {
        let pattern = #"(?:(?<=[^a-zA-Zµ°])|^)([a-zA-Zµ°]+[⁰¹²³⁴⁵⁶⁷⁸⁹]*)[ \t]*[\/⁄][ \t]*([a-zA-Zµ°]+[⁰¹²³⁴⁵⁶⁷⁸⁹]*)(?=[^a-zA-Zµ°0-9]|$)"#
        return replacePattern(text, pattern: pattern) { match, full in
            let lhs = (full as NSString).substring(with: match.range(at: 1))
            let rhs = (full as NSString).substring(with: match.range(at: 2))
            if isRecognizedUnit(lhs) && isRecognizedUnit(rhs) {
                return "\(lhs)/\(rhs)"
            }
            return (full as NSString).substring(with: match.range)
        }
    }

    public static let bibitUnits: [String: String] = [
        "kib": "Kib", "mib": "Mib", "gib": "Gib", "tib": "Tib",
        "pib": "Pib", "eib": "Eib", "zib": "Zib", "yib": "Yib"
    ]

    public static let bibyteUnits: [String: String] = [
        "kib": "KiB", "mib": "MiB", "gib": "GiB", "tib": "TiB",
        "pib": "PiB", "eib": "EiB", "zib": "ZiB", "yib": "YiB"
    ]

    /// Normalizes the casing of an individual unit word, preserving -bibit (e.g. Mib) vs -bibyte (e.g. MiB).
    public static func normalizeUnitCasing(_ word: String) -> String {
        let lower = word.lowercased()
        if let bibit = bibitUnits[lower] {
            if word.hasSuffix("B") {
                return bibyteUnits[lower] ?? bibit
            } else {
                return bibit
            }
        }
        return unitCasing[lower] ?? word
    }

    /// Normalizes all unit words within a unit string (handling compound units such as `Mib/s`, `kW/m²`, etc.).
    public static func normalizeUnitString(_ unitStr: String) -> String {
        replacePattern(unitStr, pattern: #"\b[a-zA-Z]+\b"#) { match, full in
            let word = (full as NSString).substring(with: match.range)
            return normalizeUnitCasing(word)
        }
    }

    public static let unitCasing: [String: String] = [
        // Power
        "w": "W", "kw": "kW", "mw": "MW", "gw": "GW", "hp": "hp",
        // Energy
        "j": "J", "kj": "kJ", "mj": "MJ", "gj": "GJ",
        "cal": "cal", "kcal": "kcal", "wh": "Wh", "kwh": "kWh", "mwh": "MWh",
        "ev": "eV", "btu": "BTU",
        // Mass
        "g": "g", "kg": "kg", "mg": "mg", "ug": "µg", "lb": "lb", "lbs": "lbs", "oz": "oz",
        "t": "t", "ton": "ton", "tons": "tons", "tonne": "tonne", "tonnes": "tonnes",
        // Length
        "m": "m", "km": "km", "cm": "cm", "mm": "mm", "um": "µm", "nm": "nm",
        "mi": "mi", "mile": "mile", "miles": "miles", "yd": "yd", "yard": "yard", "yards": "yards",
        "ft": "ft", "foot": "foot", "feet": "feet", "in": "in", "inch": "inch", "inches": "inches",
        // Volume
        "l": "L", "ml": "mL", "cl": "cL", "dl": "dL",
        // Time
        "s": "s", "sec": "s", "second": "s", "seconds": "s", "min": "min", "minute": "min", "minutes": "min",
        "h": "h", "hr": "h", "hour": "h", "hours": "hours", "d": "d", "day": "day", "days": "days",
        "wk": "wk", "week": "week", "weeks": "weeks", "yr": "yr", "year": "year", "years": "years",
        "ms": "ms", "ns": "ns",
        // Pressure
        "pa": "Pa", "kpa": "kPa", "mpa": "MPa", "bar": "bar", "psi": "psi", "atm": "atm",
        // Electricity
        "v": "V", "kv": "kV", "mv": "mV", "a": "A", "ma": "mA", "ka": "kA", "ohm": "Ω",
        "hz": "Hz", "khz": "kHz", "mhz": "MHz", "ghz": "GHz",
        // Digital
        "b": "B", "kb": "KB", "mb": "MB", "gb": "GB", "tb": "TB",
        "kib": "Kib", "mib": "Mib", "gib": "Gib", "tib": "Tib",
        "pib": "Pib", "eib": "Eib", "zib": "Zib", "yib": "Yib",
        // Temperature
        "celsius": "°C", "degc": "°C", "fahrenheit": "°F", "degf": "°F",
        // Speed
        "kph": "km/h", "mph": "mph"
    ]

    /// Converts characters to superscript unicode characters.
    public static func toSuperscript(_ s: String) -> String {
        String(s.map { supMap[$0] ?? $0 })
    }

    /// Converts characters to subscript unicode characters.
    public static func toSubscript(_ s: String) -> String {
        String(s.map { subMap[$0] ?? $0 })
    }

    /// Determines if a query specifies a target base (e.g. `to binary` -> 2, `to hex` -> 16, `to octal` -> 8, `to base 16` -> 16).
    public static func targetBase(from query: String) -> Int? {
        let pattern = #"(?:\b(?:to|in|as|into)\s+)(?:base\s+([0-9]+)|(binary|bin|hexadecimal|hex|octal|oct|decimal|dec))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = query as NSString
        guard let match = regex.matches(in: query, range: NSRange(location: 0, length: ns.length)).last else {
            return nil
        }
        if match.range(at: 1).location != NSNotFound {
            let baseStr = ns.substring(with: match.range(at: 1))
            return Int(baseStr)
        }
        if match.range(at: 2).location != NSNotFound {
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            switch name {
            case "binary", "bin": return 2
            case "hex", "hexadecimal": return 16
            case "octal", "oct": return 8
            case "decimal", "dec": return 10
            default: return nil
            }
        }
        return nil
    }

    /// Groups digits with a separator, e.g. groupSize: 4 for binary/hex, 3 for decimal/octal.
    public static func groupDigits(_ digits: String, groupSize: Int, separator: String) -> String {
        guard digits.count > groupSize else { return digits }
        var result = ""
        let chars = Array(digits)
        let count = chars.count
        for i in 0..<count {
            if i > 0 && (count - i) % groupSize == 0 {
                result += separator
            }
            result.append(chars[i])
        }
        return result
    }

    /// Determines if a radicand string is simple (e.g. single number or identifier) and does not need outer parentheses.
    private static func isSimpleRadicand(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            return false
        }
        let forbidden: Set<Character> = ["+", "-", "−", "*", "×", "/", "÷", " "]
        return !trimmed.contains(where: { forbidden.contains($0) })
    }

    /// Finds the degree n if a decimal string corresponds to a known unit fraction 1/n.
    private static func rootDegree(forDecimal decStr: String) -> String? {
        let trimmed = decStr.hasPrefix(".") ? ("0" + decStr) : decStr
        if let ctx = fendContext {
            if let res = try? ctx.evaluate("\(trimmed) to frac") {
                let frac = res.value.trimmingCharacters(in: .whitespaces)
                if frac.range(of: #"^1\/([0-9]+)$"#, options: .regularExpression) != nil {
                    let parts = frac.split(separator: "/")
                    if parts.count == 2 {
                        return String(parts[1]).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        if let val = Double(trimmed) {
            let candidates: [(Int, Double)] = [
                (2, 0.5),
                (3, 1.0 / 3.0),
                (4, 0.25),
                (5, 0.2),
                (6, 1.0 / 6.0),
                (7, 1.0 / 7.0),
                (8, 0.125),
                (9, 1.0 / 9.0),
                (10, 0.1),
                (16, 0.0625),
                (20, 0.05),
                (25, 0.04),
                (50, 0.02),
                (100, 0.01)
            ]
            for (n, target) in candidates {
                if abs(val - target) < 1e-4 {
                    return "\(n)"
                }
            }
        }
        return nil
    }

    /// Formats explicit sqrt(...) and cbrt(...) function calls into proper root symbols.
    private static func formatRootFunctions(_ text: String) -> String {
        var s = text
        for (funcName, symbol) in [("sqrt", "√"), ("cbrt", "∛")] {
            while true {
                guard let range = s.range(of: "\\b" + funcName + "\\b", options: .regularExpression) else {
                    break
                }
                var afterIdx = range.upperBound
                while afterIdx < s.endIndex && s[afterIdx] == " " {
                    afterIdx = s.index(after: afterIdx)
                }
                guard afterIdx < s.endIndex else { break }
                if s[afterIdx] == "(" {
                    var depth = 1
                    var curIdx = s.index(after: afterIdx)
                    while curIdx < s.endIndex && depth > 0 {
                        if s[curIdx] == "(" {
                            depth += 1
                        } else if s[curIdx] == ")" {
                            depth -= 1
                        }
                        if depth == 0 {
                            break
                        }
                        curIdx = s.index(after: curIdx)
                    }
                    if depth == 0 {
                        let inner = String(s[s.index(after: afterIdx)..<curIdx]).trimmingCharacters(in: .whitespaces)
                        let replacement: String
                        if inner.hasPrefix("(") && inner.hasSuffix(")") {
                            replacement = symbol + inner
                        } else if isSimpleRadicand(inner) {
                            replacement = symbol + inner
                        } else {
                            replacement = "\(symbol)(\(inner))"
                        }
                        s.replaceSubrange(range.lowerBound...curIdx, with: replacement)
                        continue
                    } else {
                        // Unclosed parenthesis: eager radical rendering
                        let inner = String(s[s.index(after: afterIdx)...]).trimmingCharacters(in: .whitespaces)
                        let replacement: String
                        if inner.isEmpty {
                            replacement = symbol
                        } else if inner.hasPrefix("(") && inner.hasSuffix(")") {
                            replacement = symbol + inner
                        } else if isSimpleRadicand(inner) {
                            replacement = symbol + inner
                        } else {
                            replacement = "\(symbol)(\(inner))"
                        }
                        s.replaceSubrange(range.lowerBound..<s.endIndex, with: replacement)
                        break
                    }
                } else {
                    let remaining = String(s[afterIdx...])
                    if let tokenMatch = remaining.range(of: #"^[a-zA-Z0-9_.]+"#, options: .regularExpression) {
                        let token = String(remaining[tokenMatch])
                        let fullEnd = s.index(afterIdx, offsetBy: token.count)
                        s.replaceSubrange(range.lowerBound..<fullEnd, with: symbol + token)
                        continue
                    }
                }
                break
            }
        }
        return s
    }

    /// Formats x^(1/n) and x^0.nnn into root symbols.
    private static func formatPowerRoots(_ text: String) -> String {
        var s = text
        var searchIndex = s.startIndex
        while searchIndex < s.endIndex {
            guard let caretRange = s[searchIndex...].range(of: "^") else {
                break
            }
            let caretIdx = caretRange.lowerBound
            let afterCaret = s[s.index(after: caretIdx)...]

            var foundDegree: String? = nil
            var expEndIdx = afterCaret.startIndex

            let afterCaretStr = String(afterCaret)
            if let fracMatch = afterCaretStr.range(of: #"^\(\s*1\s*\/\s*([a-zA-Z0-9_]+)\s*\)?"#, options: .regularExpression) {
                let fracStr = String(afterCaretStr[fracMatch])
                if let nMatch = fracStr.range(of: #"1\s*\/\s*([a-zA-Z0-9_]+)"#, options: .regularExpression) {
                    let parts = fracStr[nMatch].split(separator: "/")
                    if parts.count == 2 {
                        foundDegree = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    }
                }
                expEndIdx = s.index(afterCaret.startIndex, offsetBy: fracStr.count)
            } else if let decMatch = afterCaretStr.range(of: #"^(0?\.[0-9]+)"#, options: .regularExpression) {
                let decStr = String(afterCaretStr[decMatch])
                if let deg = rootDegree(forDecimal: decStr) {
                    foundDegree = deg
                    expEndIdx = s.index(afterCaret.startIndex, offsetBy: decStr.count)
                }
            }

            guard let deg = foundDegree, expEndIdx > caretIdx else {
                searchIndex = s.index(after: caretIdx)
                continue
            }

            // Find base before caret
            var beforeIdx = caretIdx
            while beforeIdx > s.startIndex {
                let prev = s.index(before: beforeIdx)
                if s[prev] == " " {
                    beforeIdx = prev
                } else {
                    break
                }
            }
            guard beforeIdx > s.startIndex else {
                searchIndex = s.index(after: caretIdx)
                continue
            }
            let charBeforeCaret = s.index(before: beforeIdx)

            var baseStartIdx = charBeforeCaret
            var radicand = ""

            if s[charBeforeCaret] == ")" {
                var depth = 1
                var cur = charBeforeCaret
                while cur > s.startIndex && depth > 0 {
                    cur = s.index(before: cur)
                    if s[cur] == ")" {
                        depth += 1
                    } else if s[cur] == "(" {
                        depth -= 1
                    }
                }
                guard depth == 0 else {
                    searchIndex = s.index(after: caretIdx)
                    continue
                }
                baseStartIdx = cur
                let inner = String(s[s.index(after: cur)..<charBeforeCaret]).trimmingCharacters(in: .whitespaces)
                if isSimpleRadicand(inner) {
                    radicand = inner
                } else {
                    radicand = "(\(inner))"
                }
            } else {
                var cur = charBeforeCaret
                while true {
                    let ch = s[cur]
                    if ch.isLetter || ch.isNumber || ch == "_" || "₀₁₂₃₄₅⁶⁷⁸⁹".contains(ch) {
                        if cur == s.startIndex {
                            baseStartIdx = cur
                            break
                        }
                        cur = s.index(before: cur)
                    } else {
                        baseStartIdx = s.index(after: cur)
                        break
                    }
                }
                guard baseStartIdx <= charBeforeCaret else {
                    searchIndex = s.index(after: caretIdx)
                    continue
                }
                radicand = String(s[baseStartIdx...charBeforeCaret])
            }

            let rootSymbol: String
            if deg == "2" {
                rootSymbol = "√"
            } else if deg == "3" {
                rootSymbol = "∛"
            } else if deg == "4" {
                rootSymbol = "∜"
            } else {
                rootSymbol = toSuperscript(deg) + "√"
            }

            let replacement = rootSymbol + radicand
            s.replaceSubrange(baseStartIdx..<expEndIdx, with: replacement)
            searchIndex = s.index(baseStartIdx, offsetBy: replacement.count)
        }
        return s
    }

    /// Formats a plain string representation of an expression or calculation result.
    public static func formatString(_ text: String, locale: Locale = .current) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("approx.") {
            s = "≈ " + s.dropFirst(7).trimmingCharacters(in: .whitespaces)
        }

        // 1. Non-decimal bases: 0x, 0b, 0o, 0d
        s = replacePattern(s, pattern: #"(\b0[xX])([0-9a-fA-F_]+)\b"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 2)).filter { $0 != "_" }
            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: 16, maxDigits: 16, sciNotDigits: 10)
            return (wasRounded ? "≈ " : "") + formatted
        }
        s = replacePattern(s, pattern: #"(\b0[bB])([01_]+)\b"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 2)).filter { $0 != "_" }
            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: 2, maxDigits: 16, sciNotDigits: 10)
            return (wasRounded ? "≈ " : "") + formatted
        }
        s = replacePattern(s, pattern: #"(\b0[oO])([0-7_]+)\b"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 2)).filter { $0 != "_" }
            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: 8, maxDigits: 16, sciNotDigits: 10)
            return (wasRounded ? "≈ " : "") + formatted
        }
        s = replacePattern(s, pattern: #"(\b0[dD])([0-9_]+)\b"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 2)).filter { $0 != "_" }
            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: 10, maxDigits: 16, sciNotDigits: 10)
            return (wasRounded ? "≈ " : "") + formatted
        }

        // 1.5. Existing non-decimal base strings exceeding 16 digits:
        s = replacePattern(s, pattern: #"(?<![0-9a-zA-Z_.])([01]{17,})\u2082"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 1))
            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: 2, maxDigits: 16, sciNotDigits: 10)
            return (wasRounded ? "≈ " : "") + formatted
        }
        s = replacePattern(s, pattern: #"(?<![0-9a-zA-Z_.])([0-9a-fA-F]{17,})\u2081\u2086"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 1))
            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: 16, maxDigits: 16, sciNotDigits: 10)
            return (wasRounded ? "≈ " : "") + formatted
        }
        s = replacePattern(s, pattern: #"(?<![0-9a-zA-Z_.])([0-7]{17,})\u2088"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 1))
            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: 8, maxDigits: 16, sciNotDigits: 10)
            return (wasRounded ? "≈ " : "") + formatted
        }

        // 2. Subscripts: log2, log10, log_2, x_1
        s = replacePattern(s, pattern: #"\blog(?:_)?([0-9]+)"#) { match, full in
            let digits = (full as NSString).substring(with: match.range(at: 1))
            return "log" + toSubscript(digits)
        }
        s = replacePattern(s, pattern: #"\b([a-zA-Z])_([0-9]+)\b"#) { match, full in
            let variable = (full as NSString).substring(with: match.range(at: 1))
            let digits = (full as NSString).substring(with: match.range(at: 2))
            return variable + toSubscript(digits)
        }

        // 2.3. Number followed by unit: 1W -> 1 W, 10km -> 10 km (avoiding scientific notation 1e+50, 1e-20)
        s = replacePattern(s, pattern: #"\b([0-9]+(?:\.[0-9]+)?)(?![eE][+-]?[0-9])([a-zA-Z]+)\b"#) { match, full in
            let num = (full as NSString).substring(with: match.range(at: 1))
            let unit = (full as NSString).substring(with: match.range(at: 2))
            return num + " " + unit
        }

        // 2.7. Format decimal numbers exceeding 16 digits to scientific notation
        s = replacePattern(s, pattern: #"(?<![a-zA-Z0-9_.])([0-9]+(?:\.[0-9]+)?)(?![a-zA-Z0-9_.eE₀-₉⁰-⁹])"#) { match, full in
            let numStr = (full as NSString).substring(with: match.range(at: 1))
            let (formatted, truncated) = Calculator.formatNumber(numStr, maxDigits: 16, sciNotDigits: 10)
            if truncated && formatted.contains("e") {
                return "≈ " + formatted
            }
            return formatted.contains("e") ? formatted : numStr
        }

        // 3. Scientific notation in results and expressions (e.g. 1.267e+30 or 1e+50)
        s = replacePattern(s, pattern: #"\b([+-]?[0-9]+(?:\.[0-9]+)?)[eE]([+-]?[0-9]+)\b"#) { match, full in
            let mantissa = (full as NSString).substring(with: match.range(at: 1))
            var exp = (full as NSString).substring(with: match.range(at: 2))
            if exp.hasPrefix("+") { exp = String(exp.dropFirst()) }
            let supExp = toSuperscript(exp)
            if mantissa == "1" {
                return "10" + supExp
            } else if mantissa == "-1" {
                return "−10" + supExp
            } else {
                return mantissa + " × 10" + supExp
            }
        }

        // 4. Root functions: sqrt(...) and cbrt(...)
        s = formatRootFunctions(s)

        // 5. Roots from powers: x^(1/n) and x^0.nnn
        s = formatPowerRoots(s)

        // 6. Exponents in expressions:
        // Parenthesized exponents: ^(2/3) -> ⁽²ᐟ³⁾, ^(x+1) -> ⁽ˣ⁺¹⁾
        s = replacePattern(s, pattern: #"\^\(([^\)]+)\)"#) { match, full in
            let exp = (full as NSString).substring(with: match.range(at: 1))
            return "⁽" + toSuperscript(exp) + "⁾"
        }
        // General and decimal powers: ^10 -> ¹⁰, ^0.75 -> ⁰˙⁷⁵
        s = replacePattern(s, pattern: #"\^([+-]?[0-9a-zA-Z.]+)"#) { match, full in
            let exp = (full as NSString).substring(with: match.range(at: 1))
            return toSuperscript(exp)
        }

        // 6. Normalize unit casing (excluding words followed by subscript base numbers)
        s = replacePattern(s, pattern: #"\b[a-zA-Z]+\b(?![₀-₉])"#) { match, full in
            let word = (full as NSString).substring(with: match.range)
            return normalizeUnitCasing(word)
        }

        // 6.5. Format unit fractions: km / h -> km⁄h, m/s -> m⁄s, W / m² -> W⁄m²
        s = formatUnitFractions(s)

        // 7. Normalize operators and spacing
        s = s.replacingOccurrences(of: #"[ \t]*\*[ \t]*"#, with: " × ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![a-zA-Zµ°])[ \t]*\/[ \t]*(?![a-zA-Zµ°])"#, with: " ÷ ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]*\+[ \t]*"#, with: " + ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\S)[ \t]*-[ \t]*(\S)"#, with: "$1 − $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^-[ \t]*"#, with: "−", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]*=[ \t]*"#, with: " = ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]*≈[ \t]*"#, with: " ≈ ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        // 8. System numbering style on decimal numbers (excluding subscripts and superscripts)
        let groupingSep = locale.groupingSeparator ?? " "
        let decimalSep = locale.decimalSeparator ?? "."
        s = replacePattern(s, pattern: #"\b([0-9]+(?:\.[0-9]+)?)\b(?![0-9a-fA-F\s]*[₀-₉])(?![⁰-⁹])"#) { match, full in
            let numStr = (full as NSString).substring(with: match.range(at: 1))
            var intPart = numStr
            var fracPart: String? = nil
            if let dotIdx = numStr.firstIndex(of: ".") {
                intPart = String(numStr[..<dotIdx])
                fracPart = String(numStr[numStr.index(after: dotIdx)...])
            }
            intPart = groupDigits(intPart, groupSize: 3, separator: groupingSep)
            if let fracPart {
                return intPart + decimalSep + fracPart
            }
            return intPart
        }

        // 8.5. Group digits for non-decimal bases (binary and hex in 4s, octal and decimal subscript in 3s)
        let escGroupingSep = NSRegularExpression.escapedPattern(for: groupingSep)
        s = replacePattern(s, pattern: "(?<![0-9a-zA-Z.])([01](?:[01\\s" + escGroupingSep + "]*[01])?)(?=\\u2082)(?!\\s*×)") { match, full in
            let raw = (full as NSString).substring(with: match.range(at: 1))
            let digits = raw.filter { $0 != " " && String($0) != groupingSep }
            guard digits.count <= 16 else { return raw }
            return groupDigits(digits, groupSize: 4, separator: groupingSep)
        }
        s = replacePattern(s, pattern: "(?<![0-9a-zA-Z.])([0-9a-fA-F](?:[0-9a-fA-F\\s" + escGroupingSep + "]*[0-9a-fA-F])?)(?=\\u2081\\u2086)(?!\\s*×)") { match, full in
            let raw = (full as NSString).substring(with: match.range(at: 1))
            let digits = raw.filter { $0 != " " && String($0) != groupingSep }
            guard digits.count <= 16 else { return raw.uppercased() }
            return groupDigits(digits.uppercased(), groupSize: 4, separator: groupingSep)
        }
        s = replacePattern(s, pattern: "(?<![0-9a-zA-Z.])([0-9a-fA-F.]+)(?=\\u2081\\u2086\\s*×)") { match, full in
            let raw = (full as NSString).substring(with: match.range(at: 1))
            return raw.uppercased()
        }
        s = replacePattern(s, pattern: "(?<![0-9a-zA-Z.])([0-7](?:[0-7\\s" + escGroupingSep + "]*[0-7])?)(?=\\u2088)(?!\\s*×)") { match, full in
            let raw = (full as NSString).substring(with: match.range(at: 1))
            let digits = raw.filter { $0 != " " && String($0) != groupingSep }
            guard digits.count <= 16 else { return raw }
            return groupDigits(digits, groupSize: 3, separator: groupingSep)
        }
        s = replacePattern(s, pattern: "(?<![0-9a-zA-Z.])([0-9](?:[0-9\\s" + escGroupingSep + "]*[0-9])?)(?=\\u2081\\u2080)(?!\\s*×)") { match, full in
            let raw = (full as NSString).substring(with: match.range(at: 1))
            let digits = raw.filter { $0 != " " && String($0) != groupingSep }
            guard digits.count <= 16 else { return raw }
            return groupDigits(digits, groupSize: 3, separator: groupingSep)
        }

        return s
    }

    public static func replacePattern(_ string: String, pattern: String, transform: (NSTextCheckingResult, String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return string }

        var result = ""
        var lastLocation = 0
        for match in matches {
            if match.range.location > lastLocation {
                result += nsString.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation))
            }
            result += transform(match, string)
            lastLocation = match.range.location + match.range.length
        }
        if lastLocation < nsString.length {
            result += nsString.substring(from: lastLocation)
        }
        return result
    }

    /// Formats an expression or result into an `AttributedString` where operators and conversion keywords are styled in gray.
    public static func format(_ text: String, locale: Locale = .current) -> AttributedString {
        let formattedString = formatString(text, locale: locale)
        var attr = AttributedString(formattedString)
        attr.foregroundColor = .primary

        let operatorChars: Set<Character> = ["+", "−", "×", "÷", "=", "≈", "√", "∛", "∜"]

        for idx in attr.characters.indices {
            let char = attr.characters[idx]
            if operatorChars.contains(char) {
                attr[idx..<attr.characters.index(after: idx)].foregroundColor = .secondary
                if char == "√" {
                    var backIdx = idx
                    while backIdx > attr.startIndex {
                        let prevIdx = attr.characters.index(before: backIdx)
                        let prevChar = attr.characters[prevIdx]
                        if "⁰¹²³⁴⁵⁶⁷⁸⁹ⁿᵏⁱˣʸ".contains(prevChar) {
                            attr[prevIdx..<backIdx].foregroundColor = .secondary
                            backIdx = prevIdx
                        } else {
                            break
                        }
                    }
                }
            }
        }

        // Color conversion keywords (to, into, as, and 'in' when not preceded by digits)
        if let regex = try? NSRegularExpression(pattern: #"(?<!\d\s)(?<!\d)\bin\b|\b(to|into|as)\b"#) {
            let nsString = formattedString as NSString
            let matches = regex.matches(in: formattedString, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if let range = Range(match.range, in: formattedString),
                   let attrRange = Range(range, in: attr) {
                    attr[attrRange].foregroundColor = .secondary
                }
            }
        }

        return attr
    }

    /// Formats calculation result spans directly into a styled AttributedString.
    /// Uses syntactic spans from FendCore without raw text regex parsing.
    public static func formatResult(
        spans: [FendSpan],
        query: String? = nil,
        locale: Locale = .current
    ) -> AttributedString {
        guard !spans.isEmpty else { return AttributedString() }

        var hasApprox = false
        var targetBase = query.flatMap { targetBase(from: $0) }

        var contentSpans: [FendSpan] = []
        for span in spans {
            let str = span.string
            if str.hasPrefix("approx. ") || str.hasPrefix("approx.") || str.hasPrefix("≈ ") || str.hasPrefix("≈") {
                hasApprox = true
            } else {
                contentSpans.append(span)
            }
        }

        guard !contentSpans.isEmpty else { return AttributedString() }

        // Infer base from spans if not explicitly specified
        if targetBase == nil || targetBase == 10 {
            if let first = contentSpans.first(where: { $0.kind == .number }) {
                let s = first.string
                if s.hasPrefix("0x") || s.hasPrefix("0X") {
                    targetBase = 16
                } else if s.hasPrefix("0b") || s.hasPrefix("0B") {
                    targetBase = 2
                } else if s.hasPrefix("0o") || s.hasPrefix("0O") {
                    targetBase = 8
                }
            }
        }

        let groupingSep = locale.groupingSeparator ?? " "
        let decimalSep = locale.decimalSeparator ?? "."

        // Non-decimal base formatting
        if let base = targetBase, base != 10 {
            let baseSubscript = toSubscript("\(base)")
            guard let numIndex = contentSpans.firstIndex(where: { $0.kind == .number }) else {
                var attr = AttributedString(contentSpans.map(\.string).joined())
                attr.foregroundColor = .primary
                return attr
            }

            var digits = contentSpans[numIndex].string.trimmingCharacters(in: .whitespaces)
            var sign = ""
            if digits.hasPrefix("-") || digits.hasPrefix("−") {
                sign = "−"
                digits = String(digits.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if digits.hasSuffix(baseSubscript) {
                digits = String(digits.dropLast(baseSubscript.count)).trimmingCharacters(in: .whitespaces)
            }
            if digits.hasPrefix("0x") || digits.hasPrefix("0X") ||
               digits.hasPrefix("0b") || digits.hasPrefix("0B") ||
               digits.hasPrefix("0o") || digits.hasPrefix("0O") {
                digits = String(digits.dropFirst(2))
            }

            let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: base, maxDigits: 16, sciNotDigits: 10)
            if wasRounded {
                hasApprox = true
            }

            var attr = AttributedString()
            if hasApprox {
                var approxAttr = AttributedString("≈ ")
                approxAttr.foregroundColor = .secondary
                attr.append(approxAttr)
            }
            if !sign.isEmpty {
                var signAttr = AttributedString(sign)
                signAttr.foregroundColor = .secondary
                attr.append(signAttr)
            }

            if formatted.contains(" × ") {
                let parts = formatted.components(separatedBy: " × ")
                var lhs = AttributedString(parts[0])
                lhs.foregroundColor = .primary
                var times = AttributedString(" × ")
                times.foregroundColor = .secondary
                var rhs = AttributedString(parts[1])
                rhs.foregroundColor = .primary
                attr.append(lhs)
                attr.append(times)
                attr.append(rhs)
            } else {
                let groupSize = (base == 16 || base == 2) ? 4 : 3
                let cleanDigits = digits.filter { $0 != " " && String($0) != groupingSep }
                let grouped = cleanDigits.count <= 16
                    ? groupDigits(base == 16 ? cleanDigits.uppercased() : cleanDigits, groupSize: groupSize, separator: groupingSep)
                    : (base == 16 ? cleanDigits.uppercased() : cleanDigits)
                var numAttr = AttributedString(grouped)
                numAttr.foregroundColor = .primary
                var subAttr = AttributedString(baseSubscript)
                subAttr.foregroundColor = .primary
                attr.append(numAttr)
                attr.append(subAttr)
            }

            // Append remaining spans (such as units)
            var needsLeadingSpace = true
            for (idx, span) in contentSpans.enumerated() {
                guard idx != numIndex else { continue }
                switch span.kind {
                case .identifier:
                    var unitStr = span.string
                    unitStr = unitStr.replacingOccurrences(of: " / ", with: "/")
                    unitStr = formatUnitFractions(unitStr)
                    let trimmed = unitStr.trimmingCharacters(in: .whitespaces)
                    let hasLeadingSpace = unitStr.hasPrefix(" ")
                    let cased = (hasLeadingSpace ? " " : "") + normalizeUnitString(trimmed)
                    if needsLeadingSpace && !cased.hasPrefix(" ") {
                        attr.append(AttributedString(" "))
                    }
                    var unitAttr = AttributedString(cased)
                    unitAttr.foregroundColor = .primary
                    attr.append(unitAttr)
                    needsLeadingSpace = cased.hasSuffix(" ")

                case .whitespace:
                    attr.append(AttributedString(span.string))
                    needsLeadingSpace = false

                case .other:
                    var sym = span.string
                    if sym == "*" { sym = " × " }
                    else if sym == "/" { sym = " ÷ " }
                    else if sym == "-" { sym = " − " }
                    var symAttr = AttributedString(sym)
                    symAttr.foregroundColor = .secondary
                    attr.append(symAttr)
                    needsLeadingSpace = sym.hasSuffix(" ")

                case .keyword:
                    var kwAttr = AttributedString(span.string)
                    kwAttr.foregroundColor = .secondary
                    attr.append(kwAttr)
                    needsLeadingSpace = span.string.hasSuffix(" ")

                default:
                    var defAttr = AttributedString(span.string)
                    defAttr.foregroundColor = .primary
                    attr.append(defAttr)
                    needsLeadingSpace = span.string.hasSuffix(" ")
                }
            }

            return attr
        }

        // Decimal formatting
        var attr = AttributedString()
        if hasApprox {
            var approxAttr = AttributedString("≈ ")
            approxAttr.foregroundColor = .secondary
            attr.append(approxAttr)
        }

        for span in contentSpans {
            switch span.kind {
            case .number:
                let (formattedNum, truncated) = Calculator.formatNumber(span.string, maxDigits: 16, sciNotDigits: 10)
                if truncated && !hasApprox {
                    var approxAttr = AttributedString("≈ ")
                    approxAttr.foregroundColor = .secondary
                    attr = approxAttr + attr
                    hasApprox = true
                }

                if let eRange = formattedNum.range(of: #"[eE][+-]?[0-9]+"#, options: .regularExpression) {
                    let mantissa = String(formattedNum[..<eRange.lowerBound])
                    var expStr = String(formattedNum[eRange])
                    expStr.removeFirst()
                    if expStr.hasPrefix("+") { expStr.removeFirst() }

                    let supExp = toSuperscript(expStr)

                    if mantissa == "1" || mantissa == "+1" {
                        var tenAttr = AttributedString("10\(supExp)")
                        tenAttr.foregroundColor = .primary
                        attr.append(tenAttr)
                    } else if mantissa == "-1" || mantissa == "−1" {
                        var signAttr = AttributedString("−")
                        signAttr.foregroundColor = .secondary
                        var tenAttr = AttributedString("10\(supExp)")
                        tenAttr.foregroundColor = .primary
                        attr.append(signAttr)
                        attr.append(tenAttr)
                    } else {
                        var intPart = mantissa
                        var fracPart: String? = nil
                        if let dotIdx = mantissa.firstIndex(of: ".") {
                            intPart = String(mantissa[..<dotIdx])
                            fracPart = String(mantissa[mantissa.index(after: dotIdx)...])
                        }
                        intPart = groupDigits(intPart, groupSize: 3, separator: groupingSep)
                        let groupedMantissa = fracPart != nil ? "\(intPart)\(decimalSep)\(fracPart!)" : intPart

                        var mantissaAttr = AttributedString(groupedMantissa)
                        mantissaAttr.foregroundColor = .primary
                        var timesAttr = AttributedString(" × ")
                        timesAttr.foregroundColor = .secondary
                        var expAttr = AttributedString("10\(supExp)")
                        expAttr.foregroundColor = .primary

                        attr.append(mantissaAttr)
                        attr.append(timesAttr)
                        attr.append(expAttr)
                    }
                } else {
                    var intPart = formattedNum
                    var fracPart: String? = nil
                    if let dotIdx = formattedNum.firstIndex(of: ".") {
                        intPart = String(formattedNum[..<dotIdx])
                        fracPart = String(formattedNum[formattedNum.index(after: dotIdx)...])
                    }
                    intPart = groupDigits(intPart, groupSize: 3, separator: groupingSep)
                    let groupedNum = fracPart != nil ? "\(intPart)\(decimalSep)\(fracPart!)" : intPart

                    var numAttr = AttributedString(groupedNum)
                    numAttr.foregroundColor = .primary
                    attr.append(numAttr)
                }

            case .identifier:
                var unitStr = span.string
                unitStr = unitStr.replacingOccurrences(of: " / ", with: "/")
                unitStr = formatUnitFractions(unitStr)
                let trimmed = unitStr.trimmingCharacters(in: .whitespaces)
                let hasLeadingSpace = unitStr.hasPrefix(" ")
                let cased = (hasLeadingSpace ? " " : "") + normalizeUnitString(trimmed)
                var unitAttr = AttributedString(cased)
                unitAttr.foregroundColor = .primary
                attr.append(unitAttr)

            case .whitespace:
                attr.append(AttributedString(span.string))

            case .other:
                var sym = span.string
                if sym == "*" { sym = " × " }
                else if sym == "/" { sym = " ÷ " }
                else if sym == "-" { sym = " − " }
                var symAttr = AttributedString(sym)
                symAttr.foregroundColor = .secondary
                attr.append(symAttr)

            case .keyword:
                var kwAttr = AttributedString(span.string)
                kwAttr.foregroundColor = .secondary
                attr.append(kwAttr)

            default:
                var defAttr = AttributedString(span.string)
                defAttr.foregroundColor = .primary
                attr.append(defAttr)
            }
        }

        return attr
    }

    /// Formats a FendResult directly into a styled AttributedString.
    public static func formatResult(
        result: FendResult,
        query: String? = nil,
        locale: Locale = .current
    ) -> AttributedString {
        formatResult(spans: result.spans, query: query, locale: locale)
    }

    /// Formats calculation result spans directly into a plain String with system numbering grouping.
    public static func formatResultString(
        spans: [FendSpan],
        query: String? = nil,
        locale: Locale = .current
    ) -> String {
        String(formatResult(spans: spans, query: query, locale: locale).characters)
    }

    /// Formats a FendResult directly into a plain String with system numbering grouping.
    public static func formatResultString(
        result: FendResult,
        query: String? = nil,
        locale: Locale = .current
    ) -> String {
        formatResultString(spans: result.spans, query: query, locale: locale)
    }
}
