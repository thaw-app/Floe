//
//  ReminderRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What adding a reminder reaches Apple Reminders through. Tests replace all of it, so none touches the real lists.
struct ReminderEnvironment {
    /// Whether Floe may write reminders. macOS asks the user the first time.
    var requestAccess: () async -> Bool = { await Reminders.requestAccess() }
    /// Adds the reminder and answers with its identifier.
    var create: (ReminderDraft) throws -> String = { try Reminders.create($0) }
    /// Deletes the reminder with that identifier. False when it is no longer there.
    var delete: (String) throws -> Bool = { try Reminders.delete($0) }
    /// The names of the user's lists, for a sentence that ends by naming one. Never asks for access: without it there are none.
    var lists: () -> [String] = { Reminders.listNames() }
}

/// Reminders, as the launcher adds them.
final class ReminderRows {
    var environment = ReminderEnvironment()
    var host = RowHost()

    /// Adds the reminder and leaves a receipt that can delete it. The task is for a test to wait on.
    @discardableResult
    func addReminder(_ draft: ReminderDraft) -> Task<Void, Never> {
        host.leave()
        return Task { [weak self, environment] in
            let isAllowed = await environment.requestAccess()
            guard let self else { return }
            guard isAllowed else {
                host.showHUD(Reminders.Failure.notAllowed.localizedDescription)
                return
            }
            do {
                let identifier = try environment.create(draft)
                host.record(Receipt(date: Date(), kind: .reminder, subject: draft.title, detail: draft.label(), identifier: identifier))
                host.showHUD(String(localized: "Added the reminder \(draft.title)", bundle: .floe, comment: "The placeholder is what the reminder is about, such as call mom."))
            } catch {
                host.showHUD(error.localizedDescription)
            }
        }
    }
}

extension ReminderRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        if case .reminderDraft = item {
            return String(localized: "Add Reminder", bundle: .floe)
        }
        return nil
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .reminderDraft(draft) = item else { return false }
        addReminder(draft)
        return true
    }
}
