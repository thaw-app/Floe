//
//  CalculatorFormatter+Roots.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

extension CalculatorFormatter {
    /// Determines if a radicand string is simple (e.g. single number or identifier) and does not need outer parentheses.
    private static func isSimpleRadicand(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") {
            return false
        }
        let forbidden: Set<Character> = ["+", "-", "−", "*", "×", "/", "÷", " "]
        return !trimmed.contains(where: { forbidden.contains($0) })
    }

    /// Finds the degree n if a decimal string corresponds to a known unit fraction 1/n.
    private static func rootDegree(forDecimal decStr: String) -> String? {
        let trimmed = decStr.hasPrefix(".") ? ("0" + decStr) : decStr
        if let ctx = fendContext, let res = try? ctx.evaluate("\(trimmed) to frac") {
            let frac = res.value.trimmingCharacters(in: .whitespaces)
            if frac.range(of: #"^1\/([0-9]+)$"#, options: .regularExpression) != nil {
                let parts = frac.split(separator: "/")
                if parts.count == 2 {
                    return String(parts[1]).trimmingCharacters(in: .whitespaces)
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
                (100, 0.01),
            ]
            for (n, target) in candidates where abs(val - target) < 1e-4 {
                return "\(n)"
            }
        }
        return nil
    }

    /// Formats explicit sqrt(...) and cbrt(...) function calls into proper root symbols.
    static func formatRootFunctions(_ text: String) -> String {
        var s = text
        for (funcName, symbol) in [("sqrt", "√"), ("cbrt", "∛")] {
            while true {
                guard let range = s.range(of: "\\b" + funcName + "\\b", options: .regularExpression) else {
                    break
                }
                var afterIdx = range.upperBound
                while afterIdx < s.endIndex, s[afterIdx] == " " {
                    afterIdx = s.index(after: afterIdx)
                }
                guard afterIdx < s.endIndex else { break }
                if s[afterIdx] == "(" {
                    var depth = 1
                    var curIdx = s.index(after: afterIdx)
                    while curIdx < s.endIndex, depth > 0 {
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
                        let inner = String(s[s.index(after: afterIdx) ..< curIdx]).trimmingCharacters(in: .whitespaces)
                        let replacement: String = if inner.hasPrefix("("), inner.hasSuffix(")") {
                            symbol + inner
                        } else if isSimpleRadicand(inner) {
                            symbol + inner
                        } else {
                            "\(symbol)(\(inner))"
                        }
                        s.replaceSubrange(range.lowerBound ... curIdx, with: replacement)
                        continue
                    } else {
                        // Unclosed parenthesis: eager radical rendering
                        let inner = String(s[s.index(after: afterIdx)...]).trimmingCharacters(in: .whitespaces)
                        let replacement: String = if inner.isEmpty {
                            symbol
                        } else if inner.hasPrefix("("), inner.hasSuffix(")") {
                            symbol + inner
                        } else if isSimpleRadicand(inner) {
                            symbol + inner
                        } else {
                            "\(symbol)(\(inner))"
                        }
                        s.replaceSubrange(range.lowerBound ..< s.endIndex, with: replacement)
                        break
                    }
                } else {
                    let remaining = String(s[afterIdx...])
                    if let tokenMatch = remaining.range(of: #"^[a-zA-Z0-9_.]+"#, options: .regularExpression) {
                        let token = String(remaining[tokenMatch])
                        let fullEnd = s.index(afterIdx, offsetBy: token.count)
                        s.replaceSubrange(range.lowerBound ..< fullEnd, with: symbol + token)
                        continue
                    }
                }
                break
            }
        }
        return s
    }

    /// Formats x^(1/n) and x^0.nnn into root symbols.
    static func formatPowerRoots(_ text: String) -> String {
        var s = text
        var searchIndex = s.startIndex
        while searchIndex < s.endIndex {
            guard let caretRange = s[searchIndex...].range(of: "^") else {
                break
            }
            let caretIdx = caretRange.lowerBound
            let afterCaret = s[s.index(after: caretIdx)...]

            var foundDegree: String?
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
                while cur > s.startIndex, depth > 0 {
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
                let inner = String(s[s.index(after: cur) ..< charBeforeCaret]).trimmingCharacters(in: .whitespaces)
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
                radicand = String(s[baseStartIdx ... charBeforeCaret])
            }

            let rootSymbol: String = if deg == "2" {
                "√"
            } else if deg == "3" {
                "∛"
            } else if deg == "4" {
                "∜"
            } else {
                toSuperscript(deg) + "√"
            }

            let replacement = rootSymbol + radicand
            s.replaceSubrange(baseStartIdx ..< expEndIdx, with: replacement)
            searchIndex = s.index(baseStartIdx, offsetBy: replacement.count)
        }
        return s
    }
}
