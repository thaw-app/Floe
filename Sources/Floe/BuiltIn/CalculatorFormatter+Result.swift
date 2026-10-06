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

public extension CalculatorFormatter {
    /// Formats calculation result spans directly into a styled AttributedString.
    /// Uses syntactic spans from FendCore without raw text regex parsing.
    static func formatResult(
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
                digits.hasPrefix("0o") || digits.hasPrefix("0O")
            {
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
                    if needsLeadingSpace, !cased.hasPrefix(" ") {
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
                    if sym == "*" {
                        sym = " × "
                    } else if sym == "/" {
                        sym = " ÷ "
                    } else if sym == "-" {
                        sym = " − "
                    }
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
                if truncated, !hasApprox {
                    var approxAttr = AttributedString("≈ ")
                    approxAttr.foregroundColor = .secondary
                    attr = approxAttr + attr
                    hasApprox = true
                }

                if let eRange = formattedNum.range(of: #"[eE][+-]?[0-9]+"#, options: .regularExpression) {
                    let mantissa = String(formattedNum[..<eRange.lowerBound])
                    var expStr = String(formattedNum[eRange])
                    expStr.removeFirst()
                    if expStr.hasPrefix("+") {
                        expStr.removeFirst()
                    }

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
                        var fracPart: String?
                        if let dotIdx = mantissa.firstIndex(of: ".") {
                            intPart = String(mantissa[..<dotIdx])
                            fracPart = String(mantissa[mantissa.index(after: dotIdx)...])
                        }
                        intPart = groupDigits(intPart, groupSize: 3, separator: groupingSep)
                        let groupedMantissa = fracPart.map { "\(intPart)\(decimalSep)\($0)" } ?? intPart

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
                    var fracPart: String?
                    if let dotIdx = formattedNum.firstIndex(of: ".") {
                        intPart = String(formattedNum[..<dotIdx])
                        fracPart = String(formattedNum[formattedNum.index(after: dotIdx)...])
                    }
                    intPart = groupDigits(intPart, groupSize: 3, separator: groupingSep)
                    let groupedNum = fracPart.map { "\(intPart)\(decimalSep)\($0)" } ?? intPart

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
                if sym == "*" {
                    sym = " × "
                } else if sym == "/" {
                    sym = " ÷ "
                } else if sym == "-" {
                    sym = " − "
                }
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
    static func formatResult(
        result: FendResult,
        query: String? = nil,
        locale: Locale = .current
    ) -> AttributedString {
        formatResult(spans: result.spans, query: query, locale: locale)
    }

    /// Formats calculation result spans directly into a plain String with system numbering grouping.
    static func formatResultString(
        spans: [FendSpan],
        query: String? = nil,
        locale: Locale = .current
    ) -> String {
        String(formatResult(spans: spans, query: query, locale: locale).characters)
    }

    /// Formats a FendResult directly into a plain String with system numbering grouping.
    static func formatResultString(
        result: FendResult,
        query: String? = nil,
        locale: Locale = .current
    ) -> String {
        formatResultString(spans: result.spans, query: query, locale: locale)
    }
}
