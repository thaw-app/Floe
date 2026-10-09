//
//  Model+MoreRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The rows that came after the first set: the shell's, receipts, checkpoints, reminders, events, timers, contacts, drafts, Focus and keywords. One place answers what Return does on
/// each, what its button says and what its menu holds, so the switches over every kind of row stay as they are.
extension LauncherModel {
    /// What Return does on one of these rows, as its button says it. Nil for any other row.
    static func laterTitle(for item: RootItem) -> String? {
        if let action = item.shellAction {
            return action.title
        }
        if case let .receipt(receipt) = item {
            return Self.undoTitle(for: receipt) ?? String(localized: "Show Details", bundle: .floe)
        }
        if case .checkpoint = item {
            return String(localized: "Resume", bundle: .floe, comment: "A verb on a button: open what a checkpoint holds.")
        }
        if case .checkpointDraft = item {
            return String(localized: "Save", bundle: .floe)
        }
        if case .keyword = item {
            return String(localized: "Type Keyword", bundle: .floe, comment: "A button that puts the selected keyword into the search field, for the user to go on typing.")
        }
        return draftTitle(for: item)
    }

    /// What Return does on a row that makes or stops something from what was typed. Nil for any other row.
    private static func draftTitle(for item: RootItem) -> String? {
        switch item {
        case .reminderDraft: String(localized: "Add Reminder", bundle: .floe)
        case .eventDraft: String(localized: "Add Event", bundle: .floe)
        case .timer(.draft): String(localized: "Start Timer", bundle: .floe)
        case .timer(.running): String(localized: "Stop Timer", bundle: .floe)
        case .contact(.person): String(localized: "Open in Contacts", bundle: .floe, comment: "Contacts is the name of Apple's app.")
        case let .focus(_, shortcut) where shortcut.isEmpty: String(localized: "Open Shortcuts", bundle: .floe, comment: "A button that opens Apple's Shortcuts app.")
        case .focus: String(localized: "Run Shortcut", bundle: .floe, comment: "A button that runs the Shortcut the user named for Focus.")
        case .outgoing: String(localized: "Open Draft", bundle: .floe, comment: "A button that opens a new email or message with the text filled in. Nothing is sent.")
        case .contact(.access): String(localized: "Open Privacy Settings", bundle: .floe, comment: "A button that opens the Privacy pane of System Settings.")
        default: nil
        }
    }

    /// What undoing a receipt is called: a file is put back, what Floe added is deleted, a note goes to the Trash. Nil when it cannot be undone.
    private static func undoTitle(for receipt: Receipt) -> String? {
        guard receipt.canUndo else { return nil }
        switch receipt.kind {
        case .reminder: return String(localized: "Delete Reminder", bundle: .floe)
        case .event: return String(localized: "Delete Event", bundle: .floe)
        case .checkpoint: return String(localized: "Delete Checkpoint", bundle: .floe)
        case .timer: return String(localized: "Stop Timer", bundle: .floe)
        case .note: return String(localized: "Move to Trash", bundle: .floe)
        default: return String(localized: "Put Back", bundle: .floe, comment: "A verb on a button: take a file out of the Trash and put it where it was.")
        }
    }

    /// Return on one of these rows.
    func openLater(_ item: RootItem) {
        if let action = item.shellAction {
            perform(action)
        } else if case let .checkpoint(checkpoint) = item {
            resume(checkpoint)
        } else if case let .checkpointDraft(name, note) = item {
            saveCheckpoint(named: name, note: note)
        } else if case let .receipt(receipt) = item, receipt.canUndo {
            undo(receipt)
        } else if case let .receipt(receipt) = item {
            showDetails(of: receipt)
        } else {
            openTyped(item)
        }
    }

    /// Return on a row that makes, stops or reaches something from what was typed.
    private func openTyped(_ item: RootItem) {
        switch item {
        case let .reminderDraft(draft): addReminder(draft)
        case let .eventDraft(draft): addEvent(draft)
        case let .timer(.draft(draft)): startTimer(draft)
        case let .timer(.running(timer)): stop(timer)
        case let .contact(row): open(row)
        case let .outgoing(draft): reach(draft.link)
        case let .focus(request, shortcut): setFocus(request, shortcut: shortcut)
        case let .keyword(hint): type(hint)
        default: break
        }
    }

    /// Puts a keyword into the search, ready for the rest to be typed after it.
    func type(_ hint: KeywordHint) {
        query = hint.typed
        focusToken += 1
    }

    /// The Actions menu of one of these rows, after what Return does.
    func laterActions(for item: RootItem) -> [ItemAction?] {
        if case let .receipt(receipt) = item {
            return receiptActions(receipt)
        }
        if case let .checkpoint(checkpoint) = item {
            return checkpointActions(checkpoint)
        }
        if case let .contact(.person(person)) = item {
            return contactActions(for: person)
        }
        return shellActions(for: item)
    }

    /// Hands a note to the app the user chose. What is written into a folder of notes leaves a receipt.
    func writeNote(_ action: NoteAction, text: String) {
        let record: (Receipt) -> Void = { [weak self] in self?.record($0) }
        Notes.perform(action, text: text, app: settings.notesApp, template: settings.notesURLTemplate, folder: settings.notesFolder, record: record) { [weak self] message in
            if let message {
                self?.showHUD(message)
            }
        }
    }

    /// Keeps a receipt of something Floe did, unless the user switched that off.
    func record(_ receipt: Receipt) {
        if settings.keepsReceipts {
            receipts.add(receipt)
        }
    }

    /// Takes back what a receipt records and says what came of it. The list stays, read again.
    func undo(_ receipt: Receipt) {
        let delete: (String) throws -> Bool = switch receipt.kind {
        case .event: scheduling.delete
        case .checkpoint: deleteCheckpoint
        case .timer: stopTimer
        default: reminding.delete
        }
        let outcome = ReceiptUndo.undo(receipt, delete: delete)
        if [.putBack, .deleted, .alreadyDeleted].contains(outcome) {
            receipts.markUndone(receipt.id)
            if receipt.kind == .extensionRemoved {
                reloadCommands()
            }
        } else if case let .trashed(moved) = outcome {
            // The move to the Trash leaves a receipt of its own, so the note can be put back.
            receipts.markUndone(receipt.id)
            record(moved)
        }
        showHUD(ReceiptUndo.message(for: outcome, subject: receipt.subject, kind: receipt.kind))
        refresh()
    }

    func showDetails(of receipt: Receipt) {
        hidePanel()
        shell.showOutput(receipt.title, receipt.text)
    }

    private func receiptActions(_ receipt: Receipt) -> [ItemAction?] {
        var actions: [ItemAction?] = []
        if receipt.canUndo {
            actions.append(ItemAction(title: String(localized: "Show Details", bundle: .floe), symbol: "doc.text") { [weak self] in self?.showDetails(of: receipt) })
        }
        if receipt.kind == .command {
            actions.append(ItemAction(title: String(localized: "Run Again", bundle: .floe), symbol: "arrow.clockwise") { [weak self] in
                self?.runShellCommand(receipt.subject, terminal: nil)
            })
        }
        return actions + [
            nil,
            ItemAction(title: String(localized: "Copy", bundle: .floe, comment: "A verb: put the selection on the clipboard."), symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(receipt.text)
                self?.showHUD(String(localized: "Copied the receipt", bundle: .floe))
            },
        ]
    }
}
