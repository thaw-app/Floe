//
//  CalculatorFormatter+Text.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

public extension CalculatorFormatter {
    /// Formats a plain string representation of an expression or calculation result.
    static func formatString(_ text: String, locale: Locale = .current) -> String {
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
            if exp.hasPrefix("+") {
                exp = String(exp.dropFirst())
            }
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
            var fracPart: String?
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

    static func replacePattern(_ string: String, pattern: String, transform: (NSTextCheckingResult, String) -> String) -> String {
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
    static func format(_ text: String, locale: Locale = .current) -> AttributedString {
        let formattedString = formatString(text, locale: locale)
        var attr = AttributedString(formattedString)
        attr.foregroundColor = .primary

        let operatorChars: Set<Character> = ["+", "−", "×", "÷", "=", "≈", "√", "∛", "∜"]

        for idx in attr.characters.indices {
            let char = attr.characters[idx]
            if operatorChars.contains(char) {
                attr[idx ..< attr.characters.index(after: idx)].foregroundColor = .secondary
                if char == "√" {
                    var backIdx = idx
                    while backIdx > attr.startIndex {
                        let prevIdx = attr.characters.index(before: backIdx)
                        let prevChar = attr.characters[prevIdx]
                        if "⁰¹²³⁴⁵⁶⁷⁸⁹ⁿᵏⁱˣʸ".contains(prevChar) {
                            attr[prevIdx ..< backIdx].foregroundColor = .secondary
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
                   let attrRange = Range(range, in: attr)
                {
                    attr[attrRange].foregroundColor = .secondary
                }
            }
        }

        return attr
    }
}
