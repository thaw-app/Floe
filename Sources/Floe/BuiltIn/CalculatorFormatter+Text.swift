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

nonisolated extension CalculatorFormatter {
    /// Formats a plain string representation of an expression or calculation result.
    static func formatString(_ text: String, locale: Locale = .current, convertExponentsToUnicode: Bool = true) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("approx.") {
            s = "≈ " + s.dropFirst(7).trimmingCharacters(in: .whitespaces)
        }
        // The order matters: each step reads what the ones before it wrote.
        s = withBasesWritten(s)
        s = withSubscripts(s)
        s = withUnitsSetOff(s)
        s = withLongNumbersShortened(s)
        s = withPowersOfTen(s, convertExponentsToUnicode: convertExponentsToUnicode)
        s = formatRootFunctions(s)
        s = formatPowerRoots(s)
        s = withPi(s)
        if convertExponentsToUnicode {
            s = withRaisedExponents(s)
        }
        s = withUnitsCased(s)
        s = formatUnitFractions(s)
        s = withOperatorsSpaced(s)
        s = withDigitsGrouped(s, locale: locale)
        return withBaseDigitsGrouped(s, separator: locale.groupingSeparator ?? " ")
    }

    private static func written(_ digits: String, inBase base: Int) -> String {
        let (formatted, wasRounded) = Calculator.formatBaseNumber(digits, base: base, maxDigits: 16, sciNotDigits: 10)
        return (wasRounded ? "≈ " : "") + formatted
    }

    /// A number with a base prefix (0x, 0b, 0o, 0d) is written with its base below the line, and one already
    /// written that way is shortened when it runs past 16 digits.
    private static func withBasesWritten(_ text: String) -> String {
        let prefixed: [(pattern: String, base: Int)] = [
            (#"(\b0[xX])([0-9a-fA-F_]+)\b"#, 16), (#"(\b0[bB])([01_]+)\b"#, 2), (#"(\b0[oO])([0-7_]+)\b"#, 8), (#"(\b0[dD])([0-9_]+)\b"#, 10),
        ]
        let long: [(pattern: String, base: Int)] = [
            (#"(?<![0-9a-zA-Z_.])([01]{17,})₂"#, 2), (#"(?<![0-9a-zA-Z_.])([0-9a-fA-F]{17,})₁₆"#, 16), (#"(?<![0-9a-zA-Z_.])([0-7]{17,})₈"#, 8),
        ]
        var s = text
        for (pattern, base) in prefixed {
            s = replacePattern(s, pattern: pattern) { groups in written(groups[2].filter { $0 != "_" }, inBase: base) }
        }
        for (pattern, base) in long {
            s = replacePattern(s, pattern: pattern) { groups in written(groups[1], inBase: base) }
        }
        return s
    }

    /// log2, log10, log_2 and x_1 take their number below the line.
    private static func withSubscripts(_ text: String) -> String {
        let logs = replacePattern(text, pattern: #"\blog(?:_)?([0-9]+)"#) { groups in "log" + toSubscript(groups[1]) }
        return replacePattern(logs, pattern: #"\b([a-zA-Z])_([0-9]+)\b"#) { groups in groups[1] + toSubscript(groups[2]) }
    }

    /// 1W -> 1 W, 10km -> 10 km, leaving the e of 1e+50 where it is.
    private static func withUnitsSetOff(_ text: String) -> String {
        replacePattern(text, pattern: #"\b([0-9]+(?:\.[0-9]+)?)(?![eE][+-]?[0-9])([a-zA-Z]+)\b"#) { groups in groups[1] + " " + groups[2] }
    }

    /// A decimal past 16 digits is shortened to a power of ten.
    private static func withLongNumbersShortened(_ text: String) -> String {
        replacePattern(text, pattern: #"(?<![a-zA-Z0-9_.])([0-9]+(?:\.[0-9]+)?)(?![a-zA-Z0-9_.eE₀-₉⁰-⁹])"#) { groups in
            let (formatted, truncated) = Calculator.formatNumber(groups[1], maxDigits: 16, sciNotDigits: 10)
            guard formatted.contains("e") else { return groups[1] }
            return (truncated ? "≈ " : "") + formatted
        }
    }

    /// 1.267e+30 -> 1.267 × 10³⁰, 1e+50 -> 10⁵⁰
    private static func withPowersOfTen(_ text: String, convertExponentsToUnicode: Bool = true) -> String {
        replacePattern(text, pattern: #"\b([+-]?[0-9]+(?:\.[0-9]+)?)[eE]([+-]?[0-9]+)\b"#) { groups in
            let rawExp = String(groups[2].trimmingPrefix("+"))
            let power = convertExponentsToUnicode ? ("10" + toSuperscript(rawExp)) : ("10^" + rawExp)
            switch groups[1] {
            case "1": return power
            case "-1": return "−" + power
            default: return groups[1] + " × " + power
            }
        }
    }

    /// ^(2/3) -> ⁽²ᐟ³⁾, ^10 -> ¹⁰, ^0.75 -> ⁰˙⁷⁵
    private static func withRaisedExponents(_ text: String) -> String {
        let bracketed = replacePattern(text, pattern: #"\^\(([^\)]+)\)"#) { groups in "⁽" + toSuperscript(groups[1]) + "⁾" }
        return replacePattern(bracketed, pattern: #"\^([+-]?[0-9a-zA-Z.]+)"#) { groups in toSuperscript(groups[1]) }
    }

    /// A unit takes the casing of its symbol, except a word that a base below the line follows.
    static func withPi(_ text: String) -> String {
        replacePattern(text, pattern: #"(?<![a-zA-Z])[pP][iI](?![a-zA-Z])"#) { _ in "π" }
    }

    private static func withUnitsCased(_ text: String) -> String {
        replacePattern(text, pattern: #"\b[a-zA-Z]+\b(?![₀-₉])"#) { groups in normalizeUnitCasing(groups[0]) }
    }

    /// The spacing passes, each compiled once, since formatting runs on every answer.
    private static let spacing: [(expression: NSRegularExpression, written: String)] = [
        (#"[ \t]*\*[ \t]*"#, " × "),
        (#"(?<![a-zA-Zµ°])[ \t]*\/[ \t]*(?![a-zA-Zµ°])"#, " ÷ "),
        (#"[ \t]*\+[ \t]*"#, " + "),
        // The operands stay outside the match, so the minus after one is found too: 1-2-3.
        (#"(?<=[^\s-])(?<!\^[^\s-])[ \t]*-[ \t]*(?=\S)"#, " − "),
        (#"\^-[ \t]*"#, "^−"),
        (#"\([ \t]*-[ \t]*"#, "(−"),
        (#"^-[ \t]*"#, "−"),
        (#"[ \t]*=[ \t]*"#, " = "),
        (#"[ \t]*≈[ \t]*"#, " ≈ "),
        (#"[ \t]+"#, " "),
    ].compactMap { pattern, written in
        (try? NSRegularExpression(pattern: pattern)).map { (expression: $0, written: written) }
    }

    private static func withOperatorsSpaced(_ text: String) -> String {
        // Each pass reads the string the one before it wrote, and a replacement changes the length,
        // so the whole range is taken from the string as it stands now, not as it came in.
        let spaced = spacing.reduce(text) { current, step in
            let whole = NSRange(location: 0, length: (current as NSString).length)
            return step.expression.stringByReplacingMatches(in: current, options: [], range: whole, withTemplate: step.written)
        }
        return spaced.trimmingCharacters(in: .whitespaces)
    }

    /// Decimal digits in the locale's groups, leaving out what is raised or sits before a base below the line.
    private static func withDigitsGrouped(_ text: String, locale: Locale) -> String {
        replacePattern(text, pattern: #"\b([0-9]+(?:\.[0-9]+)?)\b(?![0-9a-fA-F\s]*[₀-₉])(?![⁰-⁹])"#) { groups in grouped(groups[1], locale: locale) }
    }

    /// Digits before a base below the line: binary and hexadecimal in fours, octal and decimal in threes.
    private static func withBaseDigitsGrouped(_ text: String, separator: String) -> String {
        var s = groupedInBase(text, digits: "01", mark: #"₂"#, size: 4, separator: separator)
        s = groupedInBase(s, digits: "0-9a-fA-F", mark: #"₁₆"#, size: 4, separator: separator, inCapitals: true)
        s = replacePattern(s, pattern: #"(?<![0-9a-zA-Z.])([0-9a-fA-F.]+)(?=₁₆\s*×)"#) { groups in groups[1].uppercased() }
        s = groupedInBase(s, digits: "0-7", mark: #"₈"#, size: 3, separator: separator)
        return groupedInBase(s, digits: "0-9", mark: #"₁₀"#, size: 3, separator: separator)
    }

    private static func groupedInBase(_ text: String, digits set: String, mark: String, size: Int, separator: String, inCapitals: Bool = false) -> String {
        let between = set + #"\s"# + NSRegularExpression.escapedPattern(for: separator)
        return replacePattern(text, pattern: "(?<![0-9a-zA-Z.])([\(set)](?:[\(between)]*[\(set)])?)(?=\(mark))(?!\\s*×)") { groups in
            let raw = inCapitals ? groups[1].uppercased() : groups[1]
            let digits = raw.filter { $0 != " " && String($0) != separator }
            return digits.count <= 16 ? groupDigits(digits, groupSize: size, separator: separator) : raw
        }
    }

    /// Replaces each match with what `transform` makes of its groups: the whole match first, then each capture.
    static func replacePattern(_ string: String, pattern: String, transform: ([String]) -> String) -> String {
        // NSRegularExpression, since Swift's own regex has no lookbehind and five of the patterns need one.
        guard let regex = compiledPattern(pattern) else { return string }
        let source = string as NSString
        var result = ""
        var end = 0
        for match in regex.matches(in: string, range: NSRange(location: 0, length: source.length)) {
            let groups = (0 ..< match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
            result += source.substring(with: NSRange(location: end, length: match.range.location - end)) + transform(groups)
            end = match.range.location + match.range.length
        }
        return result + source.substring(from: end)
    }

    /// The patterns handed to `replacePattern` are fixed strings, so each is compiled once. It stays
    /// NSRegularExpression: Swift's own regex has no lookbehind, which five of the patterns need.
    private static let compiledPatterns = TimedCache<String, NSRegularExpression?>()

    private static func compiledPattern(_ pattern: String) -> NSRegularExpression? {
        compiledPatterns.value(for: pattern) { try? NSRegularExpression(pattern: pattern) }
    }
}
