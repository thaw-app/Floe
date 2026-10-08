//
//  CalendarEvents.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import EventKit
import Foundation

/// What `event` and a sentence asks for: an event by that title, starting when the sentence says.
nonisolated struct EventDraft: Hashable, Sendable {
    var title: String
    /// Nil when the sentence names no day or time: such a draft is shown and cannot be added.
    var start: Date?
    /// A day with no time of day is an event for the whole of it.
    var isAllDay = false

    static let keyword = "event"
    /// How long an event with a time lasts.
    static let duration: TimeInterval = 3600

    /// `event lunch with Ana Thursday noon` asks for a lunch with Ana, Thursday at twelve.
    static func request(
        in query: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        detect: (String) -> ReminderDate.Found? = ReminderDate.detected
    ) -> EventDraft? {
        let words = query.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard words.count == 2, words[0].lowercased() == keyword else { return nil }
        let text = words[1].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let reading = ReminderDate.reading(text, now: now, calendar: calendar, detect: detect)
        guard let date = reading.date else { return EventDraft(title: reading.title, start: nil) }
        return EventDraft(title: reading.title, start: reading.hasTime ? date : calendar.startOfDay(for: date), isAllDay: !reading.hasTime)
    }

    /// When it ends: an hour after it starts, or with the day it fills.
    var end: Date? {
        start.map { isAllDay ? $0 : $0.addingTimeInterval(Self.duration) }
    }

    /// Beside the title: when it starts, such as Fri 9 Oct, 5:00 pm.
    func label(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard let start else { return String(localized: "Add a day or time", bundle: .floe, comment: "Beside an event that cannot be added yet because its sentence names no date.") }
        let day = Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).day().month(.abbreviated)
        guard isAllDay else { return start.formatted(day.hour().minute()) }
        return String(localized: "\(start.formatted(day)), all day", bundle: .floe, comment: "Beside an event that fills a day. The placeholder is the day, such as Fri 9 Oct.")
    }
}

/// Apple Calendar, as far as Floe writes to it: one event added, and that one deleted again.
enum CalendarEvents {
    enum Failure: LocalizedError {
        case notAllowed, noCalendar, noStart

        var errorDescription: String? {
            switch self {
            case .notAllowed: String(localized: "Floe may not use Calendar. Allow full access in System Settings > Privacy & Security > Calendars.", bundle: .floe)
            case .noCalendar: String(localized: "Calendar has no calendar to add to.", bundle: .floe)
            case .noStart: String(localized: "Add a day or time to the event, such as Thursday noon", bundle: .floe)
            }
        }
    }

    private static let store = EKEventStore()

    /// Whether Floe may read and write events: deleting one again means finding it. macOS asks the user the first time.
    static func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                // Sendable: EventKit answers on a queue of its own.
                store.requestFullAccessToEvents { @Sendable granted, _ in continuation.resume(returning: granted) }
            }
        default:
            return false
        }
    }

    /// Adds the event to the default calendar and answers with its identifier.
    static func create(_ draft: EventDraft) throws -> String {
        guard let start = draft.start, let end = draft.end else { throw Failure.noStart }
        guard let calendar = store.defaultCalendarForNewEvents else { throw Failure.noCalendar }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.calendar = calendar
        event.startDate = start
        event.endDate = end
        event.isAllDay = draft.isAllDay
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? event.calendarItemIdentifier
    }

    /// Deletes the event with that identifier. False when it is no longer there.
    static func delete(_ identifier: String) throws -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw Failure.notAllowed }
        guard let event = store.event(withIdentifier: identifier) else { return false }
        try store.remove(event, span: .thisEvent, commit: true)
        return true
    }
}

/// `event` and a sentence leads the results with the row that adds it to Calendar.
struct EventSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard context.text(after: EventDraft.keyword) != nil, let draft = EventDraft.request(in: context.trimmed) else { return SearchContribution() }
        return SearchContribution(pinned: [RootResult(item: .eventDraft(draft), section: nil)])
    }
}
