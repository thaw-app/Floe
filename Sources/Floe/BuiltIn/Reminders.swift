//
//  Reminders.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import EventKit
import Foundation

/// What `remind` and a sentence asks for: a reminder by that title, due when the sentence says, if it says.
nonisolated struct ReminderDraft: Hashable, Sendable {
    var title: String
    var due: Date?
    /// The list the sentence ended by naming, as Reminders spells it. Nil for the default list.
    var list: String?

    static let keyword = "remind"

    /// `remind call mom tomorrow at 5pm` asks for a reminder to call mom, due tomorrow at five.
    /// `lists` are the user's lists in Reminders: a sentence that ends with `in` or `list` and one of them goes there.
    static func request(
        in query: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        lists: [String] = [],
        detect: (String) -> ReminderDate.Found? = ReminderDate.detected
    ) -> ReminderDraft? {
        let words = query.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard words.count == 2, words[0].lowercased() == keyword else { return nil }
        // "remind me to call mom" is the same request as "remind call mom".
        let text = words[1].trimmingCharacters(in: .whitespaces).replacing(#/^me\s+(to\s+)?/#.ignoresCase(), with: "")
        guard !text.isEmpty else { return nil }
        let named = named(in: text, lists: lists) { ReminderDate.reading($0, now: now, calendar: calendar, detect: detect).date != nil }
        var draft = ReminderDate.read(named?.rest ?? text, now: now, calendar: calendar, detect: detect)
        draft.list = named?.list
        return draft
    }

    /// The list a sentence ends by naming, and the sentence before those words. Nil when it names none of them.
    /// `isDate` keeps `in 2 hours` a date for a user who has a list called 2 hours.
    static func named(in text: String, lists: [String], isDate: (String) -> Bool) -> (list: String, rest: String)? {
        // The longest name first, so Home Projects is not taken for Home.
        for name in lists.sorted(by: { $0.count > $1.count }) where !name.isEmpty {
            for word in ["in list", "in", "list"] {
                guard let ending = text.range(of: " \(word) \(name)", options: [.caseInsensitive, .anchored, .backwards]) else { continue }
                let rest = text[..<ending.lowerBound].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty, !isDate("\(word) \(name)") {
                    return (name, rest)
                }
            }
        }
        return nil
    }

    /// Beside the title: when it is due, such as Fri 9 Oct, 5:00 pm, and the list when the sentence named one.
    func label(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        let when = due?.formatted(style) ?? String(localized: "No date", bundle: .floe, comment: "Beside a reminder that has no due date.")
        guard let list else { return when }
        return String(localized: "\(when) · \(list)", bundle: .floe, comment: "Beside a reminder that goes to a list the user named. The first placeholder is when it is due, the second is the list.")
    }
}

/// Reads when a reminder is due out of its sentence. The system's detector goes first, and the rules read what it misses.
nonisolated enum ReminderDate {
    /// A date and the words that said it.
    struct Found {
        var range: Range<String.Index>
        var date: Date
    }

    /// A sentence read: what is left as the title, the date it said, and whether it said a time of day with it.
    struct Reading: Equatable {
        var title: String
        var date: Date?
        var hasTime = false
    }

    static func read(_ text: String, now: Date, calendar: Calendar, detect: (String) -> Found? = detected) -> ReminderDraft {
        let reading = reading(text, now: now, calendar: calendar, detect: detect)
        return ReminderDraft(title: reading.title, due: reading.date)
    }

    static func reading(_ text: String, now: Date, calendar: Calendar, detect: (String) -> Found? = detected) -> Reading {
        let seen = detect(text)
        var found = seen
        // The detector reads a bare time as today's, even when that has passed: the rules know to take the next one.
        if (seen?.date ?? .distantPast) <= now {
            found = rule(in: text, now: now, calendar: calendar) ?? seen.map { Found(range: $0.range, date: upcoming($0.date, now: now, calendar: calendar)) }
        }
        guard let found else { return Reading(title: text) }
        return Reading(title: title(of: text, without: found.range), date: found.date, hasTime: saysATime(String(text[found.range])))
    }

    /// Whether the words of a date name a time of day: "tomorrow at 5pm" and "in 2 hours" do, "oct 15" and "on the 1st" do not.
    static func saysATime(_ words: String) -> Bool {
        words.contains(#/\d{1,2}:\d{2}|\d\s*(am|pm)\b|\bat\s+\d|\b(noon|midday|midnight|tonight|morning|afternoon|evening|minutes?|hours?)\b/#.ignoresCase())
    }

    /// The first date the system's detector finds. It reads from the clock, not from a `now` handed to it.
    static func detected(in text: String) -> Found? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).lazy.compactMap { match in
            guard let date = match.date, let range = Range(match.range, in: text) else { return nil }
            return Found(range: range, date: date)
        }.first
    }

    /// The first of the rules that reads something.
    static func rule(in text: String, now: Date, calendar: Calendar) -> Found? {
        inAWhile(text, now: now, calendar: calendar)
            ?? tonight(text, now: now, calendar: calendar)
            ?? dayOfMonth(text, now: now, calendar: calendar)
            ?? clockTime(text, now: now, calendar: calendar)
    }

    /// A day of the year that has passed, such as sep 1 in October, is next year's. Earlier today stays today.
    private static func upcoming(_ date: Date, now: Date, calendar: Calendar) -> Date {
        guard date < now, !calendar.isDate(date, inSameDayAs: now) else { return date }
        return calendar.date(byAdding: .year, value: 1, to: date) ?? date
    }

    /// The sentence without the date, and without the word that led to it: "dentist on oct 15" is "dentist".
    private static func title(of text: String, without range: Range<String.Index>) -> String {
        var before = text[..<range.lowerBound].split(separator: " ")
        if let last = before.last, ["on", "at", "by"].contains(last.lowercased()) {
            before.removeLast()
        }
        let title = (before + text[range.upperBound...].split(separator: " ")).joined(separator: " ")
        // The detector can take the whole sentence for the date, as with "lunch Thursday noon".
        return title.isEmpty ? text : title
    }

    /// `in 20 minutes`, `in 2 hours`, `in an hour`.
    private static func inAWhile(_ text: String, now: Date, calendar: Calendar) -> Found? {
        guard let match = text.firstMatch(of: #/\bin\s+(an?\s|\d{1,3}\s*)(minute|hour)s?\b/#.ignoresCase()) else { return nil }
        let count = Int(match.1.trimmingCharacters(in: .whitespaces)) ?? 1
        let unit: Calendar.Component = match.2.lowercased() == "hour" ? .hour : .minute
        return calendar.date(byAdding: unit, value: count, to: now).map { Found(range: match.range, date: $0) }
    }

    /// `tonight` is eight in the evening: today's, or tomorrow's once that has passed.
    private static func tonight(_ text: String, now: Date, calendar: Calendar) -> Found? {
        guard let match = text.firstMatch(of: #/\btonight\b/#.ignoresCase()) else { return nil }
        return next(DateComponents(hour: 20, minute: 0, second: 0), after: now, calendar: calendar).map { Found(range: match.range, date: $0) }
    }

    /// `on the 1st` is nine in the morning of the next such day. A month without a 31st is passed over.
    private static func dayOfMonth(_ text: String, now: Date, calendar: Calendar) -> Found? {
        guard let match = text.firstMatch(of: #/\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b/#.ignoresCase()),
              let day = Int(match.1), (1 ... 31).contains(day),
              let date = calendar.nextDate(after: now, matching: DateComponents(day: day, hour: 9, minute: 0, second: 0), matchingPolicy: .strict)
        else { return nil }
        return Found(range: match.range, date: date)
    }

    /// `at 3`, `at 3:30`, `at 3pm`: the next time the clock says so. Without am or pm, whichever of the two comes first.
    private static func clockTime(_ text: String, now: Date, calendar: Calendar) -> Found? {
        guard let match = text.firstMatch(of: #/\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?![\w:])/#.ignoresCase()),
              let hour = Int(match.1), let minute = Int(match.2 ?? "0"), minute < 60
        else { return nil }
        let hours: [Int]
        switch (match.3?.lowercased(), hour) {
        case ("am", 1 ... 12): hours = [hour % 12]
        case ("pm", 1 ... 12): hours = [hour % 12 + 12]
        case (nil, 1 ... 12): hours = [hour % 12, hour % 12 + 12]
        case (nil, 0), (nil, 13 ... 23): hours = [hour]
        default: return nil
        }
        let date = hours.compactMap { next(DateComponents(hour: $0, minute: minute, second: 0), after: now, calendar: calendar) }.min()
        return date.map { Found(range: match.range, date: $0) }
    }

    private static func next(_ time: DateComponents, after now: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: now, matching: time, matchingPolicy: .nextTime)
    }
}

/// Apple Reminders, as far as Floe reaches into it: one reminder added, and that one deleted again.
enum Reminders {
    enum Failure: LocalizedError {
        case notAllowed, noList

        var errorDescription: String? {
            switch self {
            case .notAllowed: String(localized: "Floe may not use Reminders. Allow it in System Settings > Privacy & Security > Reminders.", bundle: .floe)
            case .noList: String(localized: "Reminders has no list to add to.", bundle: .floe)
            }
        }
    }

    private static let store = EKEventStore()

    /// Whether Floe may write reminders. macOS asks the user the first time.
    static func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                // Sendable: EventKit answers on a queue of its own.
                store.requestFullAccessToReminders { @Sendable granted, _ in continuation.resume(returning: granted) }
            }
        default:
            return false
        }
    }

    /// The names of the user's lists. Empty until Floe may use Reminders: reading them never asks.
    static func listNames() -> [String] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        return store.calendars(for: .reminder).filter(\.allowsContentModifications).map(\.title)
    }

    /// Adds the reminder to the list its sentence named, or to the default one, and answers with its identifier.
    static func create(_ draft: ReminderDraft) throws -> String {
        let named = draft.list.flatMap { name in
            store.calendars(for: .reminder).first { $0.allowsContentModifications && $0.title.caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let list = named ?? store.defaultCalendarForNewReminders() else { throw Failure.noList }
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.calendar = list
        if let due = draft.due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    /// Deletes the reminder with that identifier. False when it is no longer there.
    static func delete(_ identifier: String) throws -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw Failure.notAllowed }
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        try store.remove(reminder, commit: true)
        return true
    }
}

/// `remind` and a sentence leads the results with the row that adds it to Reminders.
struct ReminderSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard context.text(after: ReminderDraft.keyword) != nil, let draft = ReminderDraft.request(in: context.trimmed, lists: context.reminderLists) else { return SearchContribution() }
        return SearchContribution(pinned: [RootResult(item: .reminderDraft(draft), section: nil)])
    }
}
