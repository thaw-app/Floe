//
//  Model+Events.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What adding an event reaches Apple Calendar through. Tests replace all of it, so none touches the real calendars.
struct EventEnvironment {
    /// Whether Floe may read and write events. macOS asks the user the first time.
    var requestAccess: () async -> Bool = { await CalendarEvents.requestAccess() }
    /// Adds the event and answers with its identifier.
    var create: (EventDraft) throws -> String = { try CalendarEvents.create($0) }
    /// Deletes the event with that identifier. False when it is no longer there.
    var delete: (String) throws -> Bool = { try CalendarEvents.delete($0) }
}

/// Calendar events, as the launcher adds them.
extension LauncherModel {
    /// Adds the event and leaves a receipt that can delete it. The task is for a test to wait on.
    @discardableResult
    func addEvent(_ draft: EventDraft) -> Task<Void, Never> {
        // The panel stays, so the day or time can be typed after what is there.
        guard draft.start != nil else {
            showHUD(CalendarEvents.Failure.noStart.localizedDescription)
            return Task { /* nothing to add */ }
        }
        hidePanel()
        reset()
        return Task { [weak self, scheduling] in
            let isAllowed = await scheduling.requestAccess()
            guard let self else { return }
            guard isAllowed else {
                showHUD(CalendarEvents.Failure.notAllowed.localizedDescription)
                return
            }
            do {
                let identifier = try scheduling.create(draft)
                record(Receipt(date: Date(), kind: .event, subject: draft.title, detail: draft.label(), identifier: identifier))
                showHUD(String(localized: "Added the event \(draft.title)", bundle: .floe, comment: "The placeholder is what the event is called, such as lunch with Ana."))
            } catch {
                showHUD(error.localizedDescription)
            }
        }
    }
}
