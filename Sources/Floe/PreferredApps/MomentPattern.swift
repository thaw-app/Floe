//
//  MomentPattern.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The date patterns of Moment.js, as far as daily notes use them. Obsidian names a day's note by one.
nonisolated enum MomentPattern {
    /// What Obsidian uses while its setting is empty.
    static let standard = "YYYY-MM-DD"

    // English only: Obsidian writes these names in the app's own language, which Floe cannot read from the vault.
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// The parts of a date the tokens write, in one time zone.
    private struct Day {
        var year: Int
        var month: Int
        var number: Int
        /// Sunday is one, as Calendar counts.
        var weekday: Int
        /// The ISO week of the year, which is what `W` means.
        var week: Int

        init?(_ date: Date, in zone: TimeZone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var weeks = Calendar(identifier: .iso8601)
            weeks.timeZone = zone
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            guard let year = parts.year, let month = parts.month, let number = parts.day, let weekday = parts.weekday else { return nil }
            (self.year, self.month, self.number, self.weekday) = (year, month, number, weekday)
            week = weeks.component(.weekOfYear, from: date)
        }
    }

    private static let tokens: [String: @Sendable (Day) -> String] = [
        "YYYY": { String(format: "%04d", $0.year) },
        "YY": { String(format: "%02d", $0.year % 100) },
        "MMMM": { months[$0.month - 1] },
        "MMM": { String(months[$0.month - 1].prefix(3)) },
        "MM": { String(format: "%02d", $0.month) },
        "M": { String($0.month) },
        "DD": { String(format: "%02d", $0.number) },
        "D": { String($0.number) },
        "Do": { ordinal($0.number) },
        "dddd": { weekdays[$0.weekday - 1] },
        "ddd": { String(weekdays[$0.weekday - 1].prefix(3)) },
        "WW": { String(format: "%02d", $0.week) },
        "W": { String($0.week) },
    ]

    /// A date written by a pattern, where a slash starts a subfolder. Nil for a pattern with a token Floe does not
    /// know, or one that leads out of the folder: the caller then uses the standard name, never a guess.
    static func text(_ pattern: String, for date: Date, in zone: TimeZone = .current) -> String? {
        guard let day = Day(date, in: zone) else { return nil }
        var written = ""
        var rest = pattern[...]
        while let first = rest.first {
            if first == "[" {
                guard let close = rest.firstIndex(of: "]") else { return nil }
                written += rest[rest.index(after: rest.startIndex) ..< close]
                rest = rest[rest.index(after: close)...]
            } else if first.isLetter {
                var token = String(rest.prefix { $0 == first })
                rest = rest.dropFirst(token.count)
                if token == "D", rest.first == "o" {
                    token = "Do"
                    rest = rest.dropFirst()
                }
                guard let write = tokens[token] else { return nil }
                written += write(day)
            } else {
                // A colon or a backslash is in no file name Obsidian makes.
                guard !":\\".contains(first) else { return nil }
                written.append(first)
                rest = rest.dropFirst()
            }
        }
        return staysInside(written) ? written : nil
    }

    /// Whether a path names a file under the folder it starts from: no empty step, and none that goes up or stays.
    private static func staysInside(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "." && $0 != ".." }
    }

    /// 1st, 2nd, 3rd, 4th, and 11th to 13th, as Moment writes `Do`.
    static func ordinal(_ number: Int) -> String {
        let suffix = switch (number % 10, number % 100) {
        case (_, 11 ... 13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(number)\(suffix)"
    }
}
