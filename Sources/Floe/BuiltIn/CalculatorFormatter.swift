//
//  CalculatorFormatter.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

/// Rich text formatter for calculator user inputs and outputs.
enum CalculatorFormatter {
    private static let supMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        ".": "˙", "·": "˙", "/": "ᐟ", "⁄": "ᐟ",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ",
        "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
        "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ",
        "p": "ᵖ", "q": "𐞥", "r": "ʳ", "s": "ˢ", "t": "ᵗ",
        "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "A": "ᴬ", "B": "ᴮ", "C": "ᶜ", "D": "ᴰ", "E": "ᴱ",
        "G": "ᴳ", "H": "ᴴ", "I": "ᴵ", "J": "ᴶ", "K": "ᴷ",
        "L": "ᴸ", "M": "ᴹ", "N": "ᴺ", "O": "ᴼ", "P": "ᴾ",
        "R": "ᴿ", "T": "ᵀ", "U": "ᵁ", "V": "ⱽ", "W": "ᵂ",
    ]

    static let fendContext = try? FendContext()

    private static let subMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
        "v": "ᵥ", "x": "ₓ",
    ]

    /// Two letters share one raised form, as "c" and "C" do. The plainer one is taken, the same one on every run.
    static let supToAscii = Dictionary(supMap.map { ($1, $0) }, uniquingKeysWith: plainer)
    static let subToAscii = Dictionary(subMap.map { ($1, $0) }, uniquingKeysWith: plainer)

    private static nonisolated func plainer(_ one: Character, _ other: Character) -> Character {
        if one.isASCII != other.isASCII {
            return one.isASCII ? one : other
        }
        return max(one, other)
    }

    /// Known common units to format compound unit fractions.
    static func isRecognizedUnit(_ unit: String) -> Bool {
        let stripped = unit.replacingOccurrences(of: #"[⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻ⁿ]+"#, with: "", options: .regularExpression)
        let lower = stripped.lowercased()
        let units: Set = [
            // Power & Energy
            "w", "kw", "mw", "gw", "hp", "j", "kj", "mj", "gj", "cal", "kcal", "wh", "kwh", "mwh", "ev", "btu", "n",
            // Mass & Weight
            "g", "kg", "mg", "ug", "µg", "lb", "lbs", "oz", "t", "ton", "tons", "tonne", "tonnes", "st", "stone",
            // Length & Distance
            "m", "km", "cm", "mm", "um", "µm", "nm", "pm", "mi", "mile", "miles", "yd", "yard", "yards", "ft", "foot", "feet", "in", "inch", "inches",
            // Area & Volume
            "sqm", "sqft", "acre", "acres", "ha", "hectare", "hectares", "l", "ml", "cl", "dl", "gal", "gallon", "gallons", "qt", "pt", "cup", "cups", "tbsp", "tsp", "floz",
            // Time
            "s", "sec", "second", "seconds", "min", "minute", "minutes", "h", "hr", "hour", "hours", "d", "day", "days", "wk", "week", "weeks", "yr", "year", "years", "ms", "us", "ns",
            // Temperature
            "c", "f", "k", "celsius", "fahrenheit", "kelvin", "°c", "°f",
            // Speed & Pressure
            "kph", "kmh", "mph", "mps", "knot", "knots", "pa", "kpa", "mpa", "bar", "mbar", "psi", "atm", "torr",
            // Digital
            "b", "kb", "mb", "gb", "tb", "pb", "kib", "mib", "gib", "tib", "pib", "eib", "zib", "yib", "bit", "bits", "kbit", "mbit", "gbit", "byte", "bytes",
            "kibibit", "mebibit", "gibibit", "tebibit", "pebibit", "exbibit", "zebibit", "yobibit",
            "kibibits", "mebibits", "gibibits", "tebibits", "pebibits", "exbibits", "zebibits", "yobibits",
            "kibibyte", "mebibyte", "gibibyte", "tebibyte", "pebibyte", "exbibyte", "zebibyte", "yobibyte",
            "kibibytes", "mebibytes", "gibibytes", "tebibytes", "pebibytes", "exbibytes", "zebibytes", "yobibytes",
            // Electricity & Waves
            "v", "kv", "mv", "a", "ma", "ka", "ohm", "ohms", "hz", "khz", "mhz", "ghz", "rad", "deg", "mol", "cd",
        ]
        return units.contains(lower) || unitCasing[lower] != nil || bibitUnits[lower] != nil
    }

    /// Formats compound units with division signs to render with a slash `/` without spaces instead of a division symbol `÷`.
    static func formatUnitFractions(_ text: String) -> String {
        let pattern = #"(?:(?<=[^a-zA-Zµ°])|^)([a-zA-Zµ°]+[⁰¹²³⁴⁵⁶⁷⁸⁹]*)[ \t]*[\/⁄][ \t]*([a-zA-Zµ°]+[⁰¹²³⁴⁵⁶⁷⁸⁹]*)(?=[^a-zA-Zµ°0-9]|$)"#
        return replacePattern(text, pattern: pattern) { groups in
            let lhs = groups[1]
            let rhs = groups[2]
            if isRecognizedUnit(lhs), isRecognizedUnit(rhs) {
                return "\(lhs)/\(rhs)"
            }
            return groups[0]
        }
    }

    static let bibitUnits: [String: String] = [
        "kib": "Kib", "mib": "Mib", "gib": "Gib", "tib": "Tib",
        "pib": "Pib", "eib": "Eib", "zib": "Zib", "yib": "Yib",
    ]

    static let bibyteUnits: [String: String] = [
        "kib": "KiB", "mib": "MiB", "gib": "GiB", "tib": "TiB",
        "pib": "PiB", "eib": "EiB", "zib": "ZiB", "yib": "YiB",
    ]

    /// Normalizes the casing of an individual unit word, preserving -bibit (e.g. Mib) vs -bibyte (e.g. MiB).
    static func normalizeUnitCasing(_ word: String) -> String {
        let lower = word.lowercased()
        if let bibit = bibitUnits[lower] {
            if word.hasSuffix("B") {
                return bibyteUnits[lower] ?? bibit
            } else {
                return bibit
            }
        }
        return unitCasing[lower] ?? word
    }

    /// Normalizes all unit words within a unit string (handling compound units such as `Mib/s`, `kW/m²`, etc.).
    static func normalizeUnitString(_ unitStr: String) -> String {
        replacePattern(unitStr, pattern: #"\b[a-zA-Z]+\b"#) { groups in
            let word = groups[0]
            return normalizeUnitCasing(word)
        }
    }

    static let unitCasing: [String: String] = [
        // Power
        "w": "W", "kw": "kW", "mw": "MW", "gw": "GW", "hp": "hp",
        // Energy
        "j": "J", "kj": "kJ", "mj": "MJ", "gj": "GJ",
        "cal": "cal", "kcal": "kcal", "wh": "Wh", "kwh": "kWh", "mwh": "MWh",
        "ev": "eV", "btu": "BTU",
        // Mass
        "g": "g", "kg": "kg", "mg": "mg", "ug": "µg", "lb": "lb", "lbs": "lbs", "oz": "oz",
        "t": "t", "ton": "ton", "tons": "tons", "tonne": "tonne", "tonnes": "tonnes",
        // Length
        "m": "m", "km": "km", "cm": "cm", "mm": "mm", "um": "µm", "nm": "nm",
        "mi": "mi", "mile": "mile", "miles": "miles", "yd": "yd", "yard": "yard", "yards": "yards",
        "ft": "ft", "foot": "foot", "feet": "feet", "in": "in", "inch": "inch", "inches": "inches",
        // Volume
        "l": "L", "ml": "mL", "cl": "cL", "dl": "dL",
        // Time
        // A unit fend wrote out as a word stays that word: "second" became "s" where "hours" stayed "hours".
        "s": "s", "sec": "s", "min": "min",
        "h": "h", "hr": "h", "d": "d", "day": "day", "days": "days",
        "wk": "wk", "week": "week", "weeks": "weeks", "yr": "yr", "year": "year", "years": "years",
        "ms": "ms", "ns": "ns",
        // Pressure
        "pa": "Pa", "kpa": "kPa", "mpa": "MPa", "bar": "bar", "psi": "psi", "atm": "atm",
        // Electricity
        "v": "V", "kv": "kV", "mv": "mV", "a": "A", "ma": "mA", "ka": "kA", "ohm": "Ω",
        "hz": "Hz", "khz": "kHz", "mhz": "MHz", "ghz": "GHz",
        // Digital
        "b": "B", "kb": "KB", "mb": "MB", "gb": "GB", "tb": "TB",
        "kib": "Kib", "mib": "Mib", "gib": "Gib", "tib": "Tib",
        "pib": "Pib", "eib": "Eib", "zib": "Zib", "yib": "Yib",
        // Temperature
        "celsius": "°C", "degc": "°C", "fahrenheit": "°F", "degf": "°F",
        // Speed
        "kph": "km/h", "mph": "mph",
    ]

    /// The base a number's own prefix names: 16 for 0x, 2 for 0b, 8 for 0o.
    static func prefixBase(of number: String) -> Int? {
        switch number.prefix(2).lowercased() {
        case "0x": 16
        case "0b": 2
        case "0o": 8
        default: nil
        }
    }

    /// Converts characters to superscript unicode characters.
    static func toSuperscript(_ s: String) -> String {
        String(s.map { supMap[$0] ?? $0 })
    }

    /// Converts characters to subscript unicode characters.
    static func toSubscript(_ s: String) -> String {
        String(s.map { subMap[$0] ?? $0 })
    }

    /// Determines if a query specifies a target base (e.g. `to binary` -> 2, `to hex` -> 16, `to octal` -> 8, `to base 16` -> 16).
    static func targetBase(from query: String) -> Int? {
        let pattern = #"(?:\b(?:to|in|as|into)\s+)(?:base\s+([0-9]+)|(binary|bin|hexadecimal|hex|octal|oct|decimal|dec))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = query as NSString
        guard let match = regex.matches(in: query, range: NSRange(location: 0, length: ns.length)).last else {
            return nil
        }
        if match.range(at: 1).location != NSNotFound {
            let baseStr = ns.substring(with: match.range(at: 1))
            return Int(baseStr)
        }
        if match.range(at: 2).location != NSNotFound {
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            switch name {
            case "binary", "bin": return 2
            case "hex", "hexadecimal": return 16
            case "octal", "oct": return 8
            case "decimal", "dec": return 10
            default: return nil
            }
        }
        return nil
    }

    /// Groups digits with a separator, e.g. groupSize: 4 for binary/hex, 3 for decimal/octal.
    static func groupDigits(_ digits: String, groupSize: Int, separator: String) -> String {
        guard digits.count > groupSize else { return digits }
        var result = ""
        let chars = Array(digits)
        let count = chars.count
        for i in 0 ..< count {
            if i > 0, (count - i) % groupSize == 0 {
                result += separator
            }
            result.append(chars[i])
        }
        return result
    }
}
