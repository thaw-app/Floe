//
//  ReceiptRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Receipts of what Floe did: kept, shown and undone. The resident keeps them; the panel process sends its
/// receipts to the resident and reads the list.
final class ReceiptRows {
    /// What receipts ask of the launcher.
    struct Host {
        var hidePanel: () -> Void = { /* set by LauncherFeatures */ }
        var showHUD: (String) -> Void = { _ in
            // Set by LauncherFeatures.
        }
        /// Reads the rows again: an undone receipt shows that it was.
        var refresh: () -> Void = { /* set by LauncherFeatures */ }
        /// Shows text in the output window.
        var showOutput: (_ title: String, _ text: String) -> Void = { _, _ in
            // Set by LauncherFeatures.
        }
        /// Runs a shell command again.
        var runCommand: (String) -> Void = { _ in
            // Set by LauncherFeatures.
        }
        /// An extension was put back, so the commands are scanned again.
        var commandsChanged: () -> Void = { /* set by LauncherFeatures */ }
        /// Whether the user keeps receipts.
        var keepsReceipts: () -> Bool = { true }
        /// Sends a request to the resident, in the panel process. Nil in the resident.
        var toResident: () -> ((PanelPacket) -> Void)? = { nil }
        /// Deletes what a receipt of that kind made, by its identifier. False when it is no longer there.
        var deleter: (Receipt.Kind) -> (String) throws -> Bool = { _ in { _ in false } }
    }

    /// Where receipts are kept. Tests give one of their own.
    var store = ReceiptStore.shared
    var host = Host()

    /// Keeps a receipt of something Floe did, unless the user switched that off.
    func record(_ receipt: Receipt) {
        guard host.keepsReceipts() else { return }
        if let toResident = host.toResident() {
            toResident(.receipt(receipt))
        } else {
            store.add(receipt)
        }
    }

    /// Marks completion through the resident when this is only the panel process's copy.
    private func markUndone(_ id: UUID) {
        if let toResident = host.toResident() {
            toResident(.receiptUndone(id, Date()))
        } else {
            store.markUndone(id)
        }
    }

    /// Takes back what a receipt records and says what came of it. The list stays, read again.
    func undo(_ receipt: Receipt) {
        let outcome = ReceiptUndo.undo(receipt, delete: host.deleter(receipt.kind))
        if [.putBack, .deleted, .alreadyDeleted].contains(outcome) {
            markUndone(receipt.id)
            if receipt.kind == .extensionRemoved {
                host.commandsChanged()
            }
        } else if case let .trashed(moved) = outcome {
            // The move to the Trash leaves a receipt of its own, so the note can be put back.
            markUndone(receipt.id)
            record(moved)
        }
        host.showHUD(ReceiptUndo.message(for: outcome, subject: receipt.subject, kind: receipt.kind))
        host.refresh()
    }

    func showDetails(of receipt: Receipt) {
        host.hidePanel()
        host.showOutput(receipt.title, receipt.text)
    }

    /// What undoing a receipt is called: a file is put back, what Floe added is deleted, a note goes to the Trash. Nil when it cannot be undone.
    static func undoTitle(for receipt: Receipt) -> String? {
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

    private func receiptActions(_ receipt: Receipt) -> [ItemAction?] {
        var actions: [ItemAction?] = []
        if receipt.canUndo {
            actions.append(ItemAction(title: String(localized: "Show Details", bundle: .floe), symbol: "doc.text") { [weak self] in self?.showDetails(of: receipt) })
        }
        if receipt.kind == .command {
            actions.append(ItemAction(title: String(localized: "Run Again", bundle: .floe), symbol: "arrow.clockwise") { [weak self] in
                self?.host.runCommand(receipt.subject)
            })
        }
        return actions + [
            nil,
            ItemAction(title: String(localized: "Copy", bundle: .floe, comment: "A verb: put the selection on the clipboard."), symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(receipt.text)
                self?.host.showHUD(String(localized: "Copied the receipt", bundle: .floe))
            },
        ]
    }
}

extension ReceiptRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case let .receipt(receipt) = item else { return nil }
        return Self.undoTitle(for: receipt) ?? String(localized: "Show Details", bundle: .floe)
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .receipt(receipt) = item else { return false }
        if receipt.canUndo {
            undo(receipt)
        } else {
            showDetails(of: receipt)
        }
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .receipt(receipt) = item else { return nil }
        return receiptActions(receipt)
    }
}
