//
//  SectionSearchProviders.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Upcoming events for a query that asks for the agenda, split into Today and Tomorrow.
struct CalendarSearchProvider: SearchProvider {
    /// The agenda is read through this, so a test can stand in for the user's calendars.
    var events: (String) -> [CalendarEvent] = { CalendarAgenda.shared.events(matching: $0) }

    func contribution(for context: SearchContext) -> SearchContribution {
        let agenda = events(context.query)
        let today = agenda.filter { Calendar.current.isDateInToday($0.startDate) }
        let tomorrow = agenda.filter { !Calendar.current.isDateInToday($0.startDate) }
        return SearchContribution(
            sectioned: today.map { RootResult(item: .event($0), section: String(localized: "Today", bundle: .floe)) }
                + tomorrow.map { RootResult(item: .event($0), section: String(localized: "Tomorrow", bundle: .floe)) }
        )
    }
}

/// `:` followed by a name lists the emoji and symbols that match it.
struct EmojiSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard context.query.hasPrefix(":") else { return SearchContribution() }
        let matches = EmojiCatalog.search(
            term: String(context.query.dropFirst()),
            frecency: { context.frecency(EmojiResult.id(for: $0)) }
        )
        let section = String(localized: "Emoji & Symbols", bundle: .floe)
        return SearchContribution(sectioned: matches.map { RootResult(item: .emoji($0.toned(context.emojiSkinTone)), section: section) })
    }
}
