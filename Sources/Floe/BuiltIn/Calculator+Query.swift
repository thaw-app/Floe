//
//  Calculator+Query.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import FendCore
import Foundation
import SwiftUI

extension Calculator {
    /// Determines if a query should activate the calculator UI.
    func looksLikeCalculatorQuery(_ query: String) -> Bool {
        let lower = query.lowercased()

        // Paths starting with / or ~ are file locations, not calculations
        if query.hasPrefix("/") || query.hasPrefix("~") {
            return false
        }

        // Trailing '=' forces calculator activation: {expr} =
        if query.hasSuffix("=") {
            let expr = String(query.dropLast()).trimmingCharacters(in: .whitespaces)
            // Reject if the expression itself contains '=' (no variable declarations or repeated '=')
            if expr.contains("=") {
                return false
            }
            return !expr.isEmpty
        }

        // If the query contains '=' anywhere else, reject it (no variable declarations like a=123)
        if query.contains("=") {
            return false
        }

        // Factorial expressions: e.g. 5!, 100!, 10000000!
        if lower.range(of: #"[0-9]+\s*!"#, options: .regularExpression) != nil {
            return true
        }

        // Explicit non-base-10 numbers with digits (e.g. 0xff, 0b101, 0o77)
        if isNonBaseTenNumber(lower) {
            return true
        }

        // Do not activate on just "0x", "0b", "0o" without digits
        if lower == "0x" || lower == "0b" || lower == "0o" {
            return false
        }

        // Common math constants or functions
        let mathPrefixes = [
            "pi", "tau", "e", "sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan",
            "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "ln", "log", "log2", "log10",
            "abs", "floor", "ceil", "round",
        ]
        for prefix in mathPrefixes {
            if lower == prefix || lower.hasPrefix(prefix + "(") || lower.hasPrefix(prefix + " ") {
                return true
            }
        }

        // Check for conversion keywords like "to", "in", "as"
        let conversionPatterns = [
            #"\bto\b"#,
            #"\bin\b"#,
            #"\binto\b"#,
            #"\bas\b"#,
        ]
        // Must have some number or unit expression
        for pattern in conversionPatterns where lower.range(of: pattern, options: .regularExpression) != nil {
            return true
        }

        // Query ending with conversion keyword like "10 W to" or "10W to "
        if lower.range(of: #"\b(to|in|into|as)\s*$"#, options: .regularExpression) != nil {
            return true
        }

        // Contains mathematical operators (+, -, *, /, ^, %, √, ∛, ∜, sqrt, cbrt)
        let hasOperator = query.contains("+") ||
            query.contains("-") ||
            query.contains("−") ||
            query.contains("*") ||
            query.contains("×") ||
            query.contains("/") ||
            query.contains("÷") ||
            query.contains("⁄") ||
            query.contains("^") ||
            query.contains("%") ||
            query.contains("√") ||
            query.contains("∛") ||
            query.contains("∜") ||
            query.contains("sqrt") ||
            query.contains("cbrt")

        if hasOperator {
            // Must contain at least one digit or identifier
            return query.contains(where: { $0.isNumber || $0.isLetter })
        }

        return false
    }

    /// Known common units to avoid activating calculator on arbitrary text.
    private func isRecognizedUnit(_ unit: String) -> Bool {
        let units: Set = [
            // Power & Energy
            "w", "kw", "mw", "gw", "hp", "j", "kj", "mj", "gj", "cal", "kcal", "wh", "kwh", "mwh", "ev", "btu",
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
            "b", "kb", "mb", "gb", "tb", "pb", "kib", "mib", "gib", "tib", "bit", "kbit", "mbit", "gbit", "byte", "bytes",
            // Electricity & Waves
            "v", "kv", "mv", "a", "ma", "ka", "ohm", "ohms", "hz", "khz", "mhz", "ghz", "rad", "deg",
        ]
        return units.contains(unit.lowercased())
    }

    /// Checks if expression is incomplete and awaiting more input.
    func isIncompleteExpression(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Ends with an operator
        let operatorEndings = ["+", "-", "−", "*", "×", "/", "÷", "⁄", "^", "%", "(", ",", "√", "∛", "∜"]
        for op in operatorEndings where trimmed.hasSuffix(op) {
            return true
        }

        // Unclosed parentheses awaiting more input
        var parenDepth = 0
        for ch in trimmed {
            if ch == "(" {
                parenDepth += 1
            } else if ch == ")" {
                parenDepth = max(0, parenDepth - 1)
            }
        }
        if parenDepth > 0 {
            return true
        }

        // Ends with conversion keyword: "to", "in", "as", "into"
        let conversionEndings = [
            #"\bto$"#,
            #"\bin$"#,
            #"\binto$"#,
            #"\bas$"#,
        ]
        for pattern in conversionEndings where trimmed.range(of: pattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    /// Generates a friendly error message when a unit conversion fails (e.g. "Cannot convert Power to Temperature.").
    func unitConversionErrorMessage(_ query: String, error: Error? = nil) -> String? {
        let lower = query.lowercased()
        guard let toRange = lower.range(of: #"\b(to|in|into|as)\b"#, options: .regularExpression) else {
            return nil
        }

        let leftPart = String(lower[..<toRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rightPart = String(lower[toRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !leftPart.isEmpty, !rightPart.isEmpty else { return nil }

        let fromCategory = unitCategory(leftPart)
        let toCategory = unitCategory(rightPart)

        if let from = fromCategory, let to = toCategory, from != to {
            return String(localized: "Cannot convert \(from) to \(to).", bundle: .floe, comment: "A calculator error. Both placeholders are kinds of unit, such as Length and Time.")
        }

        if let from = fromCategory, toCategory == nil {
            return String(localized: "Cannot convert \(from) to '\(rightPart)'.", bundle: .floe, comment: "A calculator error. The first placeholder is a kind of unit, such as Length; the second is what was typed.")
        }

        if let errDesc = error?.localizedDescription, !errDesc.isEmpty, !errDesc.contains("expected") {
            return errDesc
        }

        return String(localized: "Incompatible unit conversion.", bundle: .floe, comment: "A calculator error.")
    }

    /// Determines the dimensional category of a unit string.
    private func unitCategory(_ text: String) -> String? {
        let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
        let unitStr: String = if let match = lower.range(of: #"[a-zA-Z°µΩ]+$"#, options: .regularExpression) {
            String(lower[match])
        } else {
            lower
        }

        switch unitStr {
        case "w", "kw", "mw", "gw", "hp":
            return String(localized: "Power", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "j", "kj", "mj", "gj", "cal", "kcal", "wh", "kwh", "mwh", "ev", "btu":
            return String(localized: "Energy", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "g", "kg", "mg", "ug", "µg", "lb", "lbs", "oz", "t", "ton", "tons", "tonne", "tonnes", "st", "stone":
            return String(localized: "Mass", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "m", "km", "cm", "mm", "um", "µm", "nm", "pm", "mi", "mile", "miles", "yd", "yard", "yards", "ft", "foot", "feet", "in", "inch", "inches":
            return String(localized: "Length", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "sqm", "sqft", "acre", "acres", "ha", "hectare", "hectares":
            return String(localized: "Area", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "l", "ml", "cl", "dl", "gal", "gallon", "gallons", "qt", "pt", "cup", "cups", "tbsp", "tsp", "floz":
            return String(localized: "Volume", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "s", "sec", "second", "seconds", "min", "minute", "minutes", "h", "hr", "hour", "hours", "d", "day", "days", "wk", "week", "weeks", "yr", "year", "years", "ms", "us", "ns":
            return String(localized: "Time", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "c", "f", "k", "celsius", "fahrenheit", "kelvin", "°c", "°f":
            return String(localized: "Temperature", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "kph", "kmh", "mph", "mps", "knot", "knots", "km/h", "km⁄h", "m/s", "m⁄s", "mi/h", "mi⁄h", "ft/s", "ft⁄s":
            return String(localized: "Speed", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "pa", "kpa", "mpa", "bar", "mbar", "psi", "atm", "torr":
            return String(localized: "Pressure", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "b", "kb", "mb", "gb", "tb", "pb", "kib", "mib", "gib", "tib", "bit", "kbit", "mbit", "gbit", "byte", "bytes":
            return String(localized: "Digital Storage", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "v", "kv", "mv":
            return String(localized: "Voltage", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "a", "ma", "ka":
            return String(localized: "Current", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "ohm", "ohms":
            return String(localized: "Resistance", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        case "hz", "khz", "mhz", "ghz":
            return String(localized: "Frequency", bundle: .floe, comment: "A kind of unit, named in a calculator error.")
        default:
            return nil
        }
    }

    /// Rejects dice rolls (e.g. `d6`, `2d20`, `roll`) and custom function definitions (`x: x + 1`, `f = ...`).
    func isDiceOrCustomFunction(_ query: String) -> Bool {
        let lower = query.lowercased()

        // Dice patterns: standalone d6, 2d20, roll d6, etc.
        if lower.range(of: #"\b(\d*)d(\d+)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\broll\b"#, options: .regularExpression) != nil {
            return true
        }

        // Custom function patterns: `x: x + 1` or `f = x: x^2`
        if lower.range(of: #"[a-zA-Z_]\s*:\s*[a-zA-Z_]"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}
