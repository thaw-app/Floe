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

extension CalculatorFormatter {
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

    private static func withOperatorsSpaced(_ text: String) -> String {
        let spacing: [(pattern: String, written: String)] = [
            (#"[ \t]*\*[ \t]*"#, " × "),
            (#"(?<![a-zA-Zµ°])[ \t]*\/[ \t]*(?![a-zA-Zµ°])"#, " ÷ "),
            (#"[ \t]*\+[ \t]*"#, " + "),
            (#"(?<!\^)(\S)[ \t]*-[ \t]*(\S)"#, "$1 − $2"),
            (#"\^-[ \t]*"#, "^−"),
            (#"\([ \t]*-[ \t]*"#, "(−"),
            (#"^-[ \t]*"#, "−"),
            (#"[ \t]*=[ \t]*"#, " = "),
            (#"[ \t]*≈[ \t]*"#, " ≈ "),
            (#"[ \t]+"#, " "),
        ]
        return spacing.reduce(text) { $0.replacingOccurrences(of: $1.pattern, with: $1.written, options: .regularExpression) }.trimmingCharacters(in: .whitespaces)
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
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
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

    private struct FormattedSegment {
        let text: String
        let isSuperscript: Bool
    }

    private static func isFollowedByRadical(_ str: String, at index: String.Index) -> Bool {
        var scan = str.index(after: index)
        while scan < str.endIndex {
            let ch = str[scan]
            if ch == "√" { return true }
            if supToAscii[ch] != nil {
                scan = str.index(after: scan)
            } else {
                return false
            }
        }
        return false
    }

    private static func isSpaceOrTab(_ c: Character) -> Bool {
        c == " " || c == "\t"
    }

    private static func isSign(_ c: Character) -> Bool {
        c == "+" || c == "-" || c == "−"
    }

    private static func isExponentTokenChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "."
    }

    private static func isSuperscript(in s: String, at index: String.Index) -> Bool {
        supToAscii[s[index]] != nil && !isFollowedByRadical(s, at: index)
    }

    private static func isSpecialExponentStart(in s: String, at index: String.Index) -> Bool {
        s[index] == "^" || isSuperscript(in: s, at: index)
    }

    private static func parseParenthesizedExponent(
        in s: String,
        openParen: String.Index
    ) -> (segment: FormattedSegment?, nextIndex: String.Index) {
        let contentStart = s.index(after: openParen)
        var depth = 1
        var parenScan = contentStart

        while parenScan < s.endIndex {
            let c = s[parenScan]
            if c == "(" {
                depth += 1
            } else if c == ")" {
                depth -= 1
                if depth == 0 {
                    let expContent = String(s[contentStart ..< parenScan])
                    let segment = expContent.isEmpty ? nil : FormattedSegment(text: expContent, isSuperscript: true)
                    return (segment, s.index(after: parenScan))
                }
            }
            parenScan = s.index(after: parenScan)
        }

        let expContent = String(s[contentStart...])
        let segment = expContent.isEmpty ? nil : FormattedSegment(text: expContent, isSuperscript: true)
        return (segment, s.endIndex)
    }

    private static func parseSimpleExponent(
        in s: String,
        startingAt scan: String.Index
    ) -> (segment: FormattedSegment, nextIndex: String.Index)? {
        var tokenScan = scan
        if isSign(s[tokenScan]) {
            tokenScan = s.index(after: tokenScan)
            while tokenScan < s.endIndex, isSpaceOrTab(s[tokenScan]) {
                tokenScan = s.index(after: tokenScan)
            }
        }
        while tokenScan < s.endIndex, isExponentTokenChar(s[tokenScan]) {
            tokenScan = s.index(after: tokenScan)
        }
        guard tokenScan > scan else { return nil }
        let expContent = String(s[scan ..< tokenScan]).filter { !isSpaceOrTab($0) }
        return (FormattedSegment(text: expContent, isSuperscript: true), tokenScan)
    }

    private static func parseCaret(
        in s: String,
        at currentIndex: String.Index
    ) -> (segment: FormattedSegment?, nextIndex: String.Index) {
        var scan = s.index(after: currentIndex)
        while scan < s.endIndex, isSpaceOrTab(s[scan]) {
            scan = s.index(after: scan)
        }

        if scan < s.endIndex {
            if s[scan] == "(" {
                return parseParenthesizedExponent(in: s, openParen: scan)
            }
            if let result = parseSimpleExponent(in: s, startingAt: scan) {
                return result
            }
        }

        return (FormattedSegment(text: "^", isSuperscript: false), s.index(after: currentIndex))
    }

    private static func parseUnicodeSuperscripts(
        in s: String,
        startingAt currentIndex: String.Index
    ) -> (segment: FormattedSegment, nextIndex: String.Index) {
        var scan = currentIndex
        var converted = ""
        while scan < s.endIndex, let ascii = supToAscii[s[scan]], !isFollowedByRadical(s, at: scan) {
            converted.append(ascii)
            scan = s.index(after: scan)
        }
        return (FormattedSegment(text: converted, isSuperscript: true), scan)
    }

    private static func parseSegments(from s: String) -> [FormattedSegment] {
        var segments: [FormattedSegment] = []
        var currentIndex = s.startIndex

        while currentIndex < s.endIndex {
            let ch = s[currentIndex]

            // 1. Explicit caret exponent: ^(...) or ^token
            if ch == "^" {
                let (segment, nextIndex) = parseCaret(in: s, at: currentIndex)
                if let segment {
                    segments.append(segment)
                }
                currentIndex = nextIndex
                continue
            }

            // 2. Unicode superscripts that aren't radical degrees
            if isSuperscript(in: s, at: currentIndex) {
                let (segment, nextIndex) = parseUnicodeSuperscripts(in: s, startingAt: currentIndex)
                segments.append(segment)
                currentIndex = nextIndex
                continue
            }

            // 3. Regular text: accumulate until next exponent or unicode superscript
            let regStart = currentIndex
            while currentIndex < s.endIndex, !isSpecialExponentStart(in: s, at: currentIndex) {
                currentIndex = s.index(after: currentIndex)
            }
            if currentIndex > regStart {
                segments.append(FormattedSegment(text: String(s[regStart ..< currentIndex]), isSuperscript: false))
            }
        }

        return segments
    }

    private static func formatSegment(_ segment: FormattedSegment, operatorChars: Set<Character>) -> AttributedString {
        var segAttr = AttributedString(segment.text)
        segAttr.foregroundColor = .primary

        if segment.isSuperscript {
            segAttr.font = .system(size: 16, weight: .bold)
            segAttr.baselineOffset = 8
            segAttr.appKit.superscript = 1
        }

        for idx in segAttr.characters.indices where operatorChars.contains(segAttr.characters[idx]) {
            segAttr[idx ..< segAttr.characters.index(after: idx)].foregroundColor = .secondary
        }

        return segAttr
    }

    private static func styleRadicalIndices(in attr: inout AttributedString) {
        for idx in attr.characters.indices where attr.characters[idx] == "√" {
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

    private static func styleConversionKeywords(in attr: inout AttributedString) {
        let plain = String(attr.characters)
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d\s)(?<!\d)\bin\b|\b(to|into|as)\b"#) else { return }
        let nsString = plain as NSString
        let matches = regex.matches(in: plain, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            if let range = Range(match.range, in: plain),
               let attrRange = Range(range, in: attr)
            {
                attr[attrRange].foregroundColor = .secondary
            }
        }
    }

    /// Formats an expression or result into an `AttributedString` where operators and conversion keywords are styled in gray,
    /// and exponents are rendered using actual superscripts (baseline offset and smaller font) rather than unicode superscripts.
    static func format(_ text: String, locale: Locale = .current) -> AttributedString {
        let formattedString = formatString(text, locale: locale, convertExponentsToUnicode: false)
        let segments = parseSegments(from: formattedString)
        var attr = AttributedString()

        let operatorChars: Set<Character> = ["+", "−", "×", "÷", "/", "*", "^", "=", "≈", "√", "∛", "∜", "⁄"]

        for segment in segments {
            attr.append(formatSegment(segment, operatorChars: operatorChars))
        }

        styleRadicalIndices(in: &attr)
        styleConversionKeywords(in: &attr)

        return attr
    }
}
