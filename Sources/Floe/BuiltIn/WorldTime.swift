//
//  WorldTime.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `time in tokyo` and `time 5pm in berlin`: the clock somewhere else, now or at a time of day here.
nonisolated enum WorldTime {
    static let keyword = "time"

    /// Cities people ask for that the time zone database files under another one.
    private static let aliases: [String: String] = [
        "san francisco": "America/Los_Angeles", "sf": "America/Los_Angeles", "la": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "nyc": "America/New_York", "boston": "America/New_York", "washington": "America/New_York", "miami": "America/New_York",
        "austin": "America/Chicago", "dallas": "America/Chicago", "houston": "America/Chicago", "montreal": "America/Toronto",
        "cdmx": "America/Mexico_City", "guadalajara": "America/Mexico_City", "rio": "America/Sao_Paulo",
        "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin", "hamburg": "Europe/Berlin", "barcelona": "Europe/Madrid",
        "milan": "Europe/Rome", "geneva": "Europe/Zurich", "beijing": "Asia/Shanghai", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
        "bangalore": "Asia/Kolkata", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo", "abu dhabi": "Asia/Dubai", "tel aviv": "Asia/Jerusalem",
    ]

    /// Every zone's city, read from its identifier: "America/New_York" is New York. Made once, since the keyword asks on every keystroke.
    private static let cities: [(city: String, lowercased: String, identifier: String)] = TimeZone.knownTimeZoneIdentifiers.compactMap { identifier in
        guard let last = identifier.split(separator: "/").last else { return nil }
        let city = last.replacingOccurrences(of: "_", with: " ")
        return (city, city.lowercased(), identifier)
    }

    /// The zone a place name stands for, with the name to show. A city of the time zone database, one of the
    /// aliases, or an abbreviation such as UTC or PST.
    static func zone(named name: String) -> (zone: TimeZone, place: String)? {
        let wanted = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        if let identifier = aliases[wanted], let zone = TimeZone(identifier: identifier) {
            return (zone, wanted.count <= 4 ? wanted.uppercased() : wanted.capitalized)
        }
        let match = cities.first { $0.lowercased == wanted }
            ?? cities.filter { $0.lowercased.hasPrefix(wanted) && wanted.count >= 3 }.min { $0.city.count < $1.city.count }
        if let match, let zone = TimeZone(identifier: match.identifier) {
            return (zone, match.city)
        }
        return TimeZone(abbreviation: wanted.uppercased()).map { ($0, wanted.uppercased()) }
    }

    /// The time of day typed before `in`, on the day of `now` in `here`. Nil when it is not a time.
    static func moment(_ text: String, now: Date, here: TimeZone) -> Date? {
        let compact = text.lowercased().replacingOccurrences(of: " ", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = here
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = here
        for format in ["h:mma", "ha", "H:mm"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: compact) else { continue }
            let time = calendar.dateComponents([.hour, .minute], from: parsed)
            return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now)
        }
        return nil
    }

    static func row(for text: String, now: Date = Date(), here: TimeZone = .current, locale: Locale = .current) -> AnswerRow? {
        var place = text
        var moment: Date?
        if let range = text.range(of: " in ", options: [.caseInsensitive, .backwards]) {
            moment = Self.moment(String(text[..<range.lowerBound]), now: now, here: here)
            guard moment != nil else { return nil }
            place = String(text[range.upperBound...])
        } else if place.lowercased().hasPrefix("in ") {
            place = String(place.dropFirst(3))
        }
        guard let found = zone(named: place) else { return nil }
        let date = moment ?? now
        var clock = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        clock.timeZone = found.zone
        var day = Date.FormatStyle(locale: locale).weekday(.wide)
        day.timeZone = found.zone
        let time = date.formatted(clock)
        let title = String(localized: "\(time), \(date.formatted(day)) in \(found.place)", bundle: .floe, comment: "A time somewhere else. The placeholders are a time of day, a weekday and a city, as in 9:41 PM, Tuesday in Tokyo.")
        var row = AnswerRow(id: "time", text: time, subtitle: difference(from: here, to: found.zone, at: date), kind: String(localized: "Time", bundle: .floe, comment: "The kind of a result, shown beside its title. Here the time in another city."), symbol: "clock")
        row.title = title
        return row
    }

    /// How far the place's clock is from the one here, in words.
    static func difference(from here: TimeZone, to there: TimeZone, at date: Date) -> String {
        let seconds = there.secondsFromGMT(for: date) - here.secondsFromGMT(for: date)
        guard seconds != 0 else {
            return String(localized: "The same time as here", bundle: .floe)
        }
        let length = Duration.seconds(abs(seconds)).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return seconds > 0
            ? String(localized: "\(length) ahead of here", bundle: .floe, comment: "The placeholder is a length of time, such as 9 hours.")
            : String(localized: "\(length) behind here", bundle: .floe, comment: "The placeholder is a length of time, such as 9 hours.")
    }
}
