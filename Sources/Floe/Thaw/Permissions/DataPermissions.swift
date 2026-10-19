//
//  DataPermissions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Contacts
import EventKit
import SwiftUI

/// Calendar, Reminders and Contacts: each is asked for when its feature is first used, and offered up front
/// in the welcome and in Settings.
enum DataPermissions {
    static var system: [Permission] {
        [calendar, reminders, contacts]
    }

    private static var calendar: Permission {
        make(
            key: "calendar",
            title: String(localized: "Calendar", bundle: .floe, comment: "The macOS permission named Calendars."),
            iconName: "calendar",
            iconColor: .red,
            details: [
                String(localized: "Show your upcoming events and meeting links in the search.", bundle: .floe),
                String(localized: "Add an event when you type event and a sentence.", bundle: .floe, comment: "The second occurrence of event is a command the user types and stays in English."),
            ],
            summary: String(localized: "Your next events in the search, and `event` adds one.", bundle: .floe, comment: "One line on a permission card in the welcome. event is a command the user types and stays in English."),
            pane: "Privacy_Calendars",
            usageKey: "NSCalendarsFullAccessUsageDescription",
            check: { EKEventStore.authorizationStatus(for: .event) == .fullAccess },
            isUndecided: { EKEventStore.authorizationStatus(for: .event) == .notDetermined },
            ask: { await CalendarEvents.requestAccess() }
        )
    }

    private static var reminders: Permission {
        make(
            key: "reminders",
            title: String(localized: "Reminders", bundle: .floe, comment: "Apple's Reminders app, as the title of a row in Privacy."),
            iconName: "checklist",
            iconColor: .orange,
            details: [String(localized: "Add a reminder when you type remind and a sentence.", bundle: .floe, comment: "The word remind is a command the user types and stays in English.")],
            summary: String(localized: "`remind` and a sentence adds a reminder.", bundle: .floe, comment: "One line on a permission card in the welcome. remind is a command the user types and stays in English."),
            pane: "Privacy_Reminders",
            usageKey: "NSRemindersFullAccessUsageDescription",
            check: { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess },
            isUndecided: { EKEventStore.authorizationStatus(for: .reminder) == .notDetermined },
            ask: { await Reminders.requestAccess() }
        )
    }

    private static var contacts: Permission {
        make(
            key: "contacts",
            title: String(localized: "Contacts", bundle: .floe, comment: "The macOS permission named Contacts."),
            iconName: "person.crop.circle",
            iconColor: .brown,
            details: [String(localized: "Find people in your Contacts when you type contact and a name.", bundle: .floe, comment: "The word contact is a command the user types and stays in English.")],
            summary: String(localized: "`contact` and a name finds a person.", bundle: .floe, comment: "One line on a permission card in the welcome. contact is a command the user types and stays in English."),
            pane: "Privacy_Contacts",
            usageKey: "NSContactsUsageDescription",
            check: { CNContactStore.authorizationStatus(for: .contacts) == .authorized },
            isUndecided: { CNContactStore.authorizationStatus(for: .contacts) == .notDetermined },
            ask: { await ContactBook.system.requestAccess() }
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func make(
        key: String,
        title: String,
        iconName: String,
        iconColor: Color,
        details: [String],
        summary: String,
        pane: String,
        usageKey: String,
        check: @escaping () -> Bool,
        isUndecided: @escaping () -> Bool,
        ask: @escaping @Sendable () async -> Bool
    ) -> Permission {
        Permission(
            key: key,
            title: title,
            iconName: iconName,
            iconColor: iconColor,
            details: details,
            summary: summary,
            isRequired: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"),
            check: check,
            request: { completion in
                // Without the sentence that says why, macOS ends a process that asks: a build run outside its bundle.
                guard Bundle.main.object(forInfoDictionaryKey: usageKey) != nil else { return }
                // macOS asks only while the answer is open; a refusal is changed in System Settings.
                let prompts = isUndecided()
                Task {
                    let granted = await ask()
                    completion(granted, prompts)
                }
            }
        )
    }
}
