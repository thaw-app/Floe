//
//  Calculator+Result.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

public extension Calculator {
    /// Formats the result using FendResult.
    static func formatResult(_ result: FendResult, query: String? = nil) -> String {
        formatResult(spans: result.spans, query: query)
    }

    /// Formats the result from syntactic spans produced by FendCore.
    /// Replaces approximation spans with `≈` and limits precision to 16 digits, switching to scientific notation if exceeded.
    /// If the query requested a conversion to a non-decimal base, appends the base in subscript.
    static func formatResult(spans: [FendSpan], query: String? = nil) -> String {
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
                digits.hasPrefix("0o") || digits.hasPrefix("0O")
            {
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
                    if needsLeadingSpace, !cased.hasPrefix(" ") {
                        restFormatted += " "
                    }
                    restFormatted += cased
                    needsLeadingSpace = cased.hasSuffix(" ")
                case .whitespace:
                    restFormatted += span.string
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
    static func formatResult(_ value: String, query: String? = nil) -> String {
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
            FendSpan(string: s, kind: .number),
        ].compactMap(\.self)
        return formatResult(spans: spans, query: query)
    }
}
