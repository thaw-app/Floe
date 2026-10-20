//
//  CalculatorFormatter+Display.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import FloeRust
import SwiftUI

nonisolated extension CalculatorFormatter {
    private struct FormattedSegment {
        let text: String
        let isSuperscript: Bool
    }

    private static func isFollowedByRadical(_ str: String, at index: String.Index) -> Bool {
        var scan = str.index(after: index)
        while scan < str.endIndex {
            let ch = str[scan]
            if ch == "√" {
                return true
            }
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

    private static let conversionKeywords = try? NSRegularExpression(pattern: #"(?<!\d\s)(?<!\d)\bin\b|\b(to|into|as)\b"#)

    private static func styleConversionKeywords(in attr: inout AttributedString) {
        let plain = String(attr.characters)
        guard let regex = conversionKeywords else { return }
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
