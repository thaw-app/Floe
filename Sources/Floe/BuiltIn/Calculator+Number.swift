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
    static func formatNumber(_ numStr: String, maxDigits: Int = 16, sciNotDigits: Int = 10) -> (String, Bool) {
        // fend hands a complex number, a fraction or a number in another base over as one piece.
        // Only a single decimal is shortened: cutting any of those others changes what it says.
        guard numStr.wholeMatch(of: /[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/) != nil else {
            return (numStr, false)
        }
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
            return scientific(sign: sign, digits: intPart + (fracPart ?? ""), exponent: intDigitsCount - 1, precision: sciNotDigits)
        }
        if intDigitsCount > 0 {
            return shortenedDecimal(sign: sign, intPart: intPart, fracPart: fracPart, maxDigits: maxDigits)
        }
        return shortenedFraction(sign: sign, fracPart: fracPart, maxDigits: maxDigits, sciNotDigits: sciNotDigits)
    }

    private static func withoutTrailingZeros(_ digits: some StringProtocol) -> String {
        String(digits.reversed().drop(while: { $0 == "0" }).reversed())
    }

    /// Significant digits rounded to `precision` and written as a mantissa with a power of ten.
    private static func scientific(sign: String, digits: String, exponent: Int, precision: Int) -> (String, Bool) {
        var rounded = roundDigits(digits, precision: precision)
        var exp = exponent
        if rounded.count > precision {
            exp += 1
            rounded = String(rounded.prefix(precision))
        }
        let rest = withoutTrailingZeros(rounded.dropFirst())
        let mantissa = rest.isEmpty ? "\(rounded.prefix(1))" : "\(rounded.prefix(1)).\(rest)"
        let dropped = digits.count > precision ? digits.dropFirst(precision) : ""
        let wasRounded = !dropped.isEmpty && !dropped.allSatisfy { $0 == "0" } || rounded.count > digits.prefix(precision).count
        return ("\(sign)\(mantissa)e\(exp < 0 ? "" : "+")\(exp)", wasRounded)
    }

    /// A number with an integer part that fits: the fraction is cut to what is left of `maxDigits`.
    private static func shortenedDecimal(sign: String, intPart: String, fracPart: String?, maxDigits: Int) -> (String, Bool) {
        guard let fracPart else { return ("\(sign)\(intPart)", false) }
        let allowedFrac = max(0, maxDigits - intPart.count)
        if allowedFrac == 0 {
            return ("\(sign)\(intPart)", !fracPart.allSatisfy { $0 == "0" })
        }
        guard fracPart.count > allowedFrac else { return ("\(sign)\(intPart).\(fracPart)", false) }

        let combined = intPart + fracPart
        let rounded = roundDigits(combined, precision: maxDigits)
        if rounded.count > combined.prefix(maxDigits).count {
            return ("\(sign)\(rounded)e+\(intPart.count)", true)
        }
        let newFrac = withoutTrailingZeros(rounded.dropFirst(intPart.count))
        let dropped = combined.dropFirst(maxDigits)
        let wasRounded = !dropped.isEmpty && !dropped.allSatisfy { $0 == "0" }
        let newInt = rounded.prefix(intPart.count)
        return (newFrac.isEmpty ? "\(sign)\(newInt)" : "\(sign)\(newInt).\(newFrac)", wasRounded)
    }

    /// A number below one, such as "0.000123": a power of ten once the zeros alone pass `maxDigits`.
    private static func shortenedFraction(sign: String, fracPart: String?, maxDigits: Int, sciNotDigits: Int) -> (String, Bool) {
        guard let fracPart else { return ("\(sign)0", false) }
        let leadingZeros = fracPart.prefix(while: { $0 == "0" }).count
        let sigFrac = String(fracPart.dropFirst(leadingZeros))
        if sigFrac.isEmpty {
            return ("0", false)
        }
        if (leadingZeros + 1) > maxDigits {
            return scientific(sign: sign, digits: sigFrac, exponent: -(leadingZeros + 1), precision: sciNotDigits)
        }
        guard sigFrac.count > maxDigits else { return ("\(sign)0.\(fracPart)", false) }

        let rounded = roundDigits(sigFrac, precision: sciNotDigits)
        guard rounded.count > sciNotDigits else {
            return ("\(sign)0.\(withoutTrailingZeros(String(repeating: "0", count: leadingZeros) + rounded))", true)
        }
        if leadingZeros == 0 {
            return ("\(sign)1", true)
        }
        let fraction = String(repeating: "0", count: leadingZeros - 1) + String(rounded.prefix(sciNotDigits))
        return ("\(sign)0.\(withoutTrailingZeros(fraction))", true)
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
    static func formatBaseNumber(
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

        let (mantissaDigits, carried, wasRounded) = roundedMantissa(Array(intPart + (fracPart ?? "")), base: base, precision: sciNotDigits)
        guard !mantissaDigits.isEmpty else { return ("\(sign)0\(baseSubscript)", false) }

        let first = String(valueToDigit(mantissaDigits[0]))
        var restDigits = Array(mantissaDigits.dropFirst())
        while let last = restDigits.last, last == 0 {
            restDigits.removeLast()
        }
        let rest = String(restDigits.map { valueToDigit($0) })
        let mantissa = rest.isEmpty ? first : "\(first).\(rest)"

        let supExp = CalculatorFormatter.toSuperscript("\(intDigitsCount - 1 + (carried ? 1 : 0))")
        let formatted = if base != 10 {
            "\(mantissa)\(baseSubscript) × \(base)\(supExp)"
        } else if mantissa == "1" {
            "10\(supExp)"
        } else {
            "\(mantissa) × 10\(supExp)"
        }
        return ("\(sign)\(formatted)", wasRounded)
    }

    /// The leading digits of a number in a base, rounded half up to `precision` of them.
    /// `carried` says the rounding ran over into one more place, which raises the exponent by one.
    private static func roundedMantissa(_ allChars: [Character], base: Int, precision limit: Int) -> (digits: [Int], carried: Bool, wasRounded: Bool) {
        let precision = min(limit, allChars.count)
        var digits = allChars.prefix(precision).compactMap { digitValue($0) }
        guard !digits.isEmpty, allChars.count > precision else { return (digits, false, false) }

        var wasRounded = allChars[precision...].contains { (digitValue($0) ?? 0) != 0 }
        guard (digitValue(allChars[precision]) ?? 0) >= (base + 1) / 2 else { return (digits, false, wasRounded) }

        wasRounded = true
        var carry = 1
        for index in digits.indices.reversed() where carry > 0 {
            let sum = digits[index] + carry
            digits[index] = sum >= base ? sum - base : sum
            carry = sum >= base ? 1 : 0
        }
        guard carry > 0 else { return (digits, false, wasRounded) }
        digits.insert(carry, at: 0)
        return (Array(digits.prefix(limit)), true, wasRounded)
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
