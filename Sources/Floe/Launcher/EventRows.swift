//
//  EventRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What adding an event reaches Apple Calendar through. Tests replace all of it, so none touches the real calendars.
struct EventEnvironment {
    /// Whether Floe may read and write events. macOS asks the user the first time.
    var requestAccess: () async -> Bool = { await CalendarEvents.requestAccess() }
    /// Adds the event and answers with its identifier.
    var create: (EventDraft) throws -> String = { try CalendarEvents.create($0) }
    /// Deletes the event with that identifier. False when it is no longer there.
    var delete: (String) throws -> Bool = { try CalendarEvents.delete($0) }
}

/// Calendar events, as the launcher adds and opens them.
final class EventRows {
    var environment = EventEnvironment()
    var host = RowHost()
    /// Opens a link in the browser the role says.
    var openLink: (URL) -> Void = { _ in
        // Set by LauncherFeatures.
    }

    /// Adds the event and leaves a receipt that can delete it. The task is for a test to wait on.
    @discardableResult
    func addEvent(_ draft: EventDraft) -> Task<Void, Never> {
        // The panel stays, so the day or time can be typed after what is there.
        guard draft.start != nil else {
            host.showHUD(CalendarEvents.Failure.noStart.localizedDescription)
            return Task { /* nothing to add */ }
        }
        host.leave()
        return Task { [weak self, environment] in
            let isAllowed = await environment.requestAccess()
            guard let self else { return }
            guard isAllowed else {
                host.showHUD(CalendarEvents.Failure.notAllowed.localizedDescription)
                return
            }
            do {
                let identifier = try environment.create(draft)
                host.record(Receipt(date: Date(), kind: .event, subject: draft.title, detail: draft.label(), identifier: identifier))
                host.showHUD(String(localized: "Added the event \(draft.title)", bundle: .floe, comment: "The placeholder is what the event is called, such as lunch with Ana."))
            } catch {
                host.showHUD(error.localizedDescription)
            }
        }
    }

    /// Opens an event of the day's agenda: its meeting when it has a link to one, else the calendar.
    func open(_ event: CalendarEvent) {
        if let destination = event.meetingURL ?? event.calendarURL {
            openLink(destination)
        }
        host.leave()
    }
}

extension EventRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        if case .eventDraft = item {
            return String(localized: "Add Event", bundle: .floe)
        }
        return nil
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case let .eventDraft(draft): addEvent(draft)
        case let .event(event): open(event)
        default: return false
        }
        return true
    }
}
