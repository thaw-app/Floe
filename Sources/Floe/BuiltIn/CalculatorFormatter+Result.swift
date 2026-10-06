//
//  CalculatorFormatter+Result.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

extension CalculatorFormatter {
    /// How a piece of a result is coloured when it is drawn.
    enum Tone {
        case figure, quiet, unmarked
    }

    /// A run of a result's text.
    struct ResultPiece: Equatable {
        var text: String
        var tone: Tone = .figure
    }

    /// The text Return copies keeps every digit. The text the view draws is shortened and grouped as the locale groups.
    enum ResultStyle {
        case copied
        case drawn(Locale)
    }

    /// A result as pieces, from the spans fend returns. One reading for the copied text and the drawn one.
    static func resultPieces(spans: [FendSpan], query: String?, style: ResultStyle) -> [ResultPiece] {
        var isApproximate = spans.contains { isApproximationMark($0.string) }
        let content = spans.filter { !isApproximationMark($0.string) }
        guard !content.isEmpty else { return [] }

        let pieces: [ResultPiece]
        if let base = base(of: content, query: query), base != 10 {
            guard let number = content.firstIndex(where: { $0.kind == .number }) else {
                return approximation(isApproximate) + [ResultPiece(text: content.map(\.string).joined())]
            }
            pieces = piecesInBase(base, content: content, number: number, style: style, isApproximate: &isApproximate)
        } else {
            pieces = decimalPieces(content, style: style, isApproximate: &isApproximate)
        }
        return approximation(isApproximate) + pieces
    }

    /// Formats calculation result spans into the styled text the view draws.
    static func formatResult(spans: [FendSpan], query: String? = nil, locale: Locale = .current) -> AttributedString {
        resultPieces(spans: spans, query: query, style: .drawn(locale)).reduce(into: AttributedString()) { text, piece in
            var run = AttributedString(piece.text)
            switch piece.tone {
            case .figure: run.foregroundColor = .primary
            case .quiet: run.foregroundColor = .secondary
            case .unmarked: break
            }
            text.append(run)
        }
    }

    // MARK: Reading the spans

    private static func isApproximationMark(_ text: String) -> Bool {
        text.hasPrefix("approx.") || text.hasPrefix("≈")
    }

    private static func approximation(_ isApproximate: Bool) -> [ResultPiece] {
        isApproximate ? [ResultPiece(text: "≈ ", tone: .quiet)] : []
    }

    /// The base the query asks for, or the one the first number's own prefix names.
    private static func base(of content: [FendSpan], query: String?) -> Int? {
        let asked = query.flatMap { targetBase(from: $0) }
        if asked == nil || asked == 10, let first = content.first(where: { $0.kind == .number }), let named = prefixBase(of: first.string) {
            return named
        }
        return asked
    }

    /// A unit as Floe writes it: no spaces round a division, fractions joined, and the casing of its symbol.
    private static func unitText(_ span: FendSpan) -> String {
        let unit = formatUnitFractions(span.string.replacingOccurrences(of: " / ", with: "/"))
        let normalized = normalizeUnitString(unit.trimmingCharacters(in: .whitespaces))
        let written = withPi(normalized)
        return (unit.hasPrefix(" ") ? " " : "") + written
    }

    private static func symbolText(_ symbol: String) -> String {
        switch symbol {
        case "*": " × "
        case "/": " ÷ "
        case "-": " − "
        default: symbol
        }
    }

    // MARK: Decimal

    private static func decimalPieces(_ content: [FendSpan], style: ResultStyle, isApproximate: inout Bool) -> [ResultPiece] {
        content.flatMap { span -> [ResultPiece] in
            switch (span.kind, style) {
            case (.number, .copied):
                // The digits are fend's, all of them.
                return [ResultPiece(text: span.string)]
            case let (.number, .drawn(locale)):
                let (number, wasShortened) = Calculator.formatNumber(span.string, maxDigits: 16, sciNotDigits: 10)
                isApproximate = isApproximate || wasShortened
                return drawnNumber(number, locale: locale)
            case (.identifier, _):
                return [ResultPiece(text: unitText(span))]
            case (.whitespace, _):
                return [ResultPiece(text: span.string, tone: .unmarked)]
            case (.other, .drawn):
                return [ResultPiece(text: symbolText(span.string), tone: .quiet)]
            case (.keyword, .drawn):
                return [ResultPiece(text: span.string, tone: .quiet)]
            default:
                return [ResultPiece(text: span.string)]
            }
        }
    }

    /// A decimal as it is drawn: digits in the locale's groups, and a power of ten where it was shortened to one.
    private static func drawnNumber(_ number: String, locale: Locale) -> [ResultPiece] {
        guard let exponent = number.range(of: #"[eE][+-]?[0-9]+"#, options: .regularExpression) else {
            return [ResultPiece(text: grouped(number, locale: locale))]
        }
        let mantissa = String(number[..<exponent.lowerBound])
        let power = ResultPiece(text: "10" + toSuperscript(String(number[exponent].dropFirst().trimmingPrefix("+"))))
        switch mantissa {
        case "1", "+1": return [power]
        case "-1", "−1": return [ResultPiece(text: "−", tone: .quiet), power]
        default: return [ResultPiece(text: grouped(mantissa, locale: locale)), ResultPiece(text: " × ", tone: .quiet), power]
        }
    }

    static func grouped(_ number: String, locale: Locale) -> String {
        let parts = number.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = groupDigits(String(parts[0]), groupSize: 3, separator: locale.groupingSeparator ?? " ")
        return parts.count > 1 ? whole + (locale.decimalSeparator ?? ".") + parts[1] : whole
    }

    // MARK: Another base

    private static func piecesInBase(_ base: Int, content: [FendSpan], number: Int, style: ResultStyle, isApproximate: inout Bool) -> [ResultPiece] {
        let mark = toSubscript("\(base)")
        var digits = content[number].string.trimmingCharacters(in: .whitespaces)
        let isNegative = digits.hasPrefix("-") || digits.hasPrefix("−")
        if isNegative {
            digits = String(digits.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if digits.hasSuffix(mark) {
            digits = String(digits.dropLast(mark.count)).trimmingCharacters(in: .whitespaces)
        }
        if prefixBase(of: digits) != nil {
            digits = String(digits.dropFirst(2))
        }
        let (written, wasShortened) = Calculator.formatBaseNumber(digits, base: base, maxDigits: 16, sciNotDigits: 10)
        isApproximate = isApproximate || wasShortened

        let sign = isNegative ? [ResultPiece(text: "−", tone: style.isDrawn ? .quiet : .figure)] : []
        return sign + numberInBase(base, digits: digits, written: written, mark: mark, style: style) + piecesAfterNumber(content, number: number, style: style)
    }

    private static func numberInBase(_ base: Int, digits: String, written: String, mark: String, style: ResultStyle) -> [ResultPiece] {
        guard case let .drawn(locale) = style else { return [ResultPiece(text: written)] }
        if let times = written.range(of: " × ") {
            return [ResultPiece(text: String(written[..<times.lowerBound])), ResultPiece(text: " × ", tone: .quiet), ResultPiece(text: String(written[times.upperBound...]))]
        }
        let separator = locale.groupingSeparator ?? " "
        let clean = digits.filter { $0 != " " && String($0) != separator }
        let shown = base == 16 ? clean.uppercased() : clean
        let groups = clean.count <= 16 ? groupDigits(shown, groupSize: base == 16 || base == 2 ? 4 : 3, separator: separator) : shown
        return [ResultPiece(text: groups + mark)]
    }

    /// What follows a number in another base, a unit most often, set off by one space.
    private static func piecesAfterNumber(_ content: [FendSpan], number: Int, style _: ResultStyle) -> [ResultPiece] {
        var pieces: [ResultPiece] = []
        var needsSpace = true
        for (index, span) in content.enumerated() where index != number {
            switch span.kind {
            case .identifier:
                let unit = unitText(span)
                if needsSpace, !unit.hasPrefix(" ") {
                    pieces.append(ResultPiece(text: " ", tone: .unmarked))
                }
                pieces.append(ResultPiece(text: unit))
                needsSpace = unit.hasSuffix(" ")
            case .whitespace:
                pieces.append(ResultPiece(text: span.string, tone: .unmarked))
                needsSpace = false
            case .other:
                let symbol = symbolText(span.string)
                pieces.append(ResultPiece(text: symbol, tone: .quiet))
                needsSpace = symbol.hasSuffix(" ")
            default:
                pieces.append(ResultPiece(text: span.string, tone: span.kind == .keyword ? .quiet : .figure))
                needsSpace = span.string.hasSuffix(" ")
            }
        }
        return pieces
    }
}

private extension CalculatorFormatter.ResultStyle {
    var isDrawn: Bool {
        if case .drawn = self {
            return true
        }
        return false
    }
}
