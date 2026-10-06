//
//  Calculator+Number.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

extension Calculator {
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
            let wasRounded = !dropped.isEmpty && !dropped.allSatisfy { $0 == "0" } || rounded.count > allDigits.prefix(sciNotDigits).count
            return ("\(sign)\(mantissa)e+\(exp)", wasRounded)
        } else if intDigitsCount > 0 {
            // Integer is <= maxDigits
            if let fracPart {
                let allowedFrac = max(0, maxDigits - intDigitsCount)
                if allowedFrac == 0 {
                    let wasRounded = !fracPart.allSatisfy { $0 == "0" }
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
                    let wasRounded = !dropped.isEmpty && !dropped.allSatisfy { $0 == "0" }
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
                let wasRounded = !dropped.isEmpty && !dropped.allSatisfy { $0 == "0" } || rounded.count > sigFrac.prefix(sciNotDigits).count
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
        if let v = c.wholeNumberValue {
            return v
        }
        if let ascii = c.asciiValue {
            if ascii >= 65, ascii <= 90 {
                return Int(ascii - 65 + 10)
            }
            if ascii >= 97, ascii <= 122 {
                return Int(ascii - 97 + 10)
            }
        }
        return nil
    }

    /// Converts an integer value 0..<36 to a digit character.
    private static func valueToDigit(_ v: Int, uppercase: Bool = true) -> Character {
        if v < 10 {
            return Character("\(v)")
        }
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
            let fracStr = fracPart.map { ".\($0)" } ?? ""
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
        let formatted = if base == 10 {
            if mantissa == "1" {
                "10\(supExp)"
            } else {
                "\(mantissa) × 10\(supExp)"
            }
        } else {
            "\(mantissa)\(baseSubscript) × \(base)\(supExp)"
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
        var arr = take.compactMap(\.wholeNumberValue)
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
