//
//  Calculator+Shorthand.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What people type that fend reads differently, or not at all, rewritten into what fend does read.
extension Calculator {
    func withShorthandExpanded(_ query: String) -> String {
        var s = withDatesNamed(query)
        s = Self.withTemperatureLetters(s)
        s = Self.withFeetAndInches(s)
        return Self.withPercentOfTheLeftSide(s)
    }

    /// fend 1.5.8 cannot be told what day it is, so "today" is written as the date itself: @2026-10-06.
    private func withDatesNamed(_ query: String) -> String {
        let days = ["today": 0, "tomorrow": 1, "yesterday": -1]
        return CalculatorFormatter.replacePattern(query, pattern: #"(?i)\b(today|tomorrow|yesterday)\b"#) { groups in
            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.date(byAdding: .day, value: days[groups[1].lowercased()] ?? 0, to: now()) ?? now()
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return String(format: "@%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }

    /// "100 f to c": fend knows the scales as F, C and K, and a small f is a prefix to it.
    private static func withTemperatureLetters(_ query: String) -> String {
        CalculatorFormatter.replacePattern(query, pattern: #"^\s*(-?[0-9]+(?:\.[0-9]+)?)\s*°?\s*([fFcCkK])\s+(to|in|as)\s+°?\s*([fFcCkK])\s*$"#) { groups in
            "\(groups[1]) \(groups[2].uppercased()) \(groups[3]) \(groups[4].uppercased())"
        }
    }

    /// "5 ft 10 in to cm": fend reads feet with "inches" after them, and takes a bare "in" there for the word
    /// that starts a conversion. Only that "in" is spelled out, where the line ends or a conversion follows.
    private static func withFeetAndInches(_ query: String) -> String {
        let number = #"([0-9]+(?:\.[0-9]+)?)"#
        let pattern = #"(?i)\b"# + number + #"\s*(ft|feet|foot)\s+"# + number + #"\s*in\b(?=\s*$|\s+(?:to|as|in)\b)"#
        return CalculatorFormatter.replacePattern(query, pattern: pattern) { groups in
            "\(groups[1]) \(groups[2]) \(groups[3]) inches"
        }
    }

    /// "200 + 10%" is 220 to the person typing it and 200.1 to fend, where a percent is a hundredth.
    /// A percentage added, taken off or multiplied in is one of what stands beside it, unless that is a percentage too.
    private static func withPercentOfTheLeftSide(_ query: String) -> String {
        let number = #"([0-9]+(?:\.[0-9]+)?)"#
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let added = trimmed.wholeMatch(of: /(.+?)\s*([+\-−])\s*([0-9]+(?:\.[0-9]+)?)\s*%/), isAmount(String(added.1)) {
            return "(\(added.1)) * (1 \(added.2 == "+" ? "+" : "-") \(added.3)/100)"
        }
        if let multiplied = trimmed.wholeMatch(of: /(.+?)\s*[*×]\s*([0-9]+(?:\.[0-9]+)?)\s*%/), isAmount(String(multiplied.1)) {
            return "(\(multiplied.1)) * (\(multiplied.2)/100)"
        }
        return CalculatorFormatter.replacePattern(trimmed, pattern: "^" + number + #"\s*%\s*[*×]\s*([^%]+)$"#) { groups in
            "(\(groups[1])/100) * (\(groups[2]))"
        }
    }

    /// Something a percentage can be taken of: no percentage in it, and not cut off at an operator or an open bracket.
    private static func isAmount(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return !text.contains("%") && !"+-−*×/÷^(".contains(last)
    }
}
