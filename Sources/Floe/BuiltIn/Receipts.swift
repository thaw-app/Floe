//
//  Receipts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A record of something Floe did that changed the Mac: what, when, and how to take it back if that can be done.
nonisolated struct Receipt: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case command, trash, process, extensionRemoved, reminder, event
        /// A note written as a new file, a line added to the day's note, and a checkpoint saved.
        case note, noteLine, checkpoint
    }

    var id = UUID()
    var date: Date
    var kind: Kind
    /// What it was done to: the command, the file's name, the process, the extension, the title of a reminder or an event, a checkpoint's name.
    var subject: String
    /// What came of it: a command's first line of output, the path a file was at.
    var detail: String
    /// For what went to the Trash: where it was, and where in the Trash it is. For a note Floe wrote, `original` is where it is.
    var original: String?
    var trashed: String?
    /// For what Floe added and can delete again: what Reminders or Calendar knows it by, or a checkpoint's id.
    var identifier: String?
    /// For a note Floe wrote: its size and when it was last changed, as they were when the writing was done.
    var size: Int?
    var modified: Date?
    var undone: Date?

    /// Receipts written before events have the identifier under the name it had then.
    private enum CodingKeys: String, CodingKey {
        case id, date, kind, subject, detail, original, trashed, size, modified, undone
        case identifier = "reminder"
    }

    /// What went to the Trash can be put back, what Floe added deleted, and a note it wrote moved to the Trash.
    /// A command that ran, a process that quit and a line added to a note cannot be taken back.
    var canUndo: Bool {
        guard undone == nil else { return false }
        if kind == .note {
            return original != nil && size != nil && modified != nil
        }
        return identifier != nil || (original != nil && trashed != nil)
    }

    var title: String {
        switch kind {
        case .command: String(localized: "Ran \(subject)", bundle: .floe, comment: "A receipt. The placeholder is a shell command.")
        case .trash: String(localized: "Moved \(subject) to the Trash", bundle: .floe, comment: "A receipt. The placeholder is a file name.")
        case .process: String(localized: "Quit \(subject)", bundle: .floe, comment: "A receipt. The placeholder is a program's name.")
        case .extensionRemoved: String(localized: "Removed the extension \(subject)", bundle: .floe, comment: "A receipt. The placeholder is an extension's name.")
        case .reminder: String(localized: "Added the reminder \(subject)", bundle: .floe, comment: "The placeholder is what the reminder is about, such as call mom.")
        case .event: String(localized: "Added the event \(subject)", bundle: .floe, comment: "The placeholder is what the event is called, such as lunch with Ana.")
        case .note: String(localized: "Wrote the note \(subject)", bundle: .floe, comment: "A receipt. The placeholder is the name of a note's file.")
        case .noteLine: String(localized: "Added a line to the note \(subject)", bundle: .floe, comment: "A receipt. The placeholder is the name of a note's file, such as 2026-10-08.")
        case .checkpoint: String(localized: "Saved the checkpoint \(subject)", bundle: .floe, comment: "A receipt. The placeholder is the name the user gave a checkpoint.")
        }
    }

    /// Beside the title: when, and whether it can be taken back or was.
    func label(now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let when = formatter.localizedString(for: date, relativeTo: now)
        if kind == .note {
            return undone != nil
                ? String(localized: "\(when) · moved to the Trash", bundle: .floe, comment: "Beside the receipt of a note that was moved to the Trash again. The placeholder is a time, such as 2 hr. ago.")
                : String(localized: "\(when) · can be moved to the Trash", bundle: .floe, comment: "Beside the receipt of a note Floe wrote. The placeholder is a time, such as 2 hr. ago.")
        }
        if identifier != nil {
            return undone != nil
                ? String(localized: "\(when) · deleted", bundle: .floe, comment: "Beside the receipt of something Floe added that was deleted again. The placeholder is a time, such as 2 hr. ago.")
                : String(localized: "\(when) · can be deleted", bundle: .floe, comment: "Beside the receipt of something Floe added. The placeholder is a time, such as 2 hr. ago.")
        }
        if undone != nil {
            return String(localized: "\(when) · put back", bundle: .floe, comment: "Beside a receipt. The placeholder is a time, such as 2 hr. ago.")
        }
        return canUndo ? String(localized: "\(when) · can be put back", bundle: .floe, comment: "Beside a receipt. The placeholder is a time, such as 2 hr. ago.") : when
    }

    /// Everything the receipt holds, for the window and the clipboard.
    var text: String {
        var lines = [title, date.formatted(date: .abbreviated, time: .standard)]
        if !detail.isEmpty {
            lines.append(detail)
        }
        if let undone {
            lines.append(undoneLine(undone.formatted(date: .abbreviated, time: .standard)))
        } else if kind == .noteLine {
            lines.append(String(localized: "This cannot be undone: the note may have been edited since Floe added the line.", bundle: .floe))
        } else if !canUndo {
            lines.append(String(localized: "This cannot be undone.", bundle: .floe))
        }
        return lines.joined(separator: "\n")
    }

    private func undoneLine(_ when: String) -> String {
        if kind == .note {
            return String(localized: "Moved to the Trash \(when)", bundle: .floe, comment: "When a note Floe wrote was moved to the Trash again. The placeholder is a date and time.")
        }
        return identifier != nil
            ? String(localized: "Deleted \(when)", bundle: .floe, comment: "When something Floe added was deleted again. The placeholder is a date and time.")
            : String(localized: "Put back \(when)", bundle: .floe, comment: "The placeholder is a date and time.")
    }

    /// The receipt of a note written as a new file, with the size and date that say later whether it was changed.
    static func note(_ file: URL, now: Date = Date(), fileManager: FileManager = .default) -> Receipt {
        let attributes = try? fileManager.attributesOfItem(atPath: file.path)
        var receipt = Receipt(date: now, kind: .note, subject: file.deletingPathExtension().lastPathComponent, detail: (file.path as NSString).abbreviatingWithTildeInPath, original: file.path)
        receipt.size = (attributes?[.size] as? NSNumber)?.intValue
        receipt.modified = attributes?[.modificationDate] as? Date
        return receipt
    }

    /// The receipt of a checkpoint saved. One that took the place of an older one says that deleting it brings none back.
    static func saved(_ checkpoint: Checkpoint, replacing: Bool) -> Receipt {
        var detail = checkpoint.summary
        if replacing {
            detail += "\n" + String(localized: "It replaced an older checkpoint of the same name. Deleting this one does not bring the older one back.", bundle: .floe)
        }
        return Receipt(date: checkpoint.saved, kind: .checkpoint, subject: checkpoint.name, detail: detail, identifier: checkpoint.id.uuidString)
    }

    /// The receipt of a line added to the day's note: where the note is, and the line.
    static func noteLine(_ text: String, in file: URL, now: Date = Date()) -> Receipt {
        let place = (file.path as NSString).abbreviatingWithTildeInPath
        return Receipt(date: now, kind: .noteLine, subject: file.deletingPathExtension().lastPathComponent, detail: "\(place)\n\(text)")
    }
}

/// Taking back what a receipt records: a file out of the Trash without writing over anything newer, what Floe
/// added deleted again, and a note it wrote moved to the Trash while it is as Floe left it.
nonisolated enum ReceiptUndo {
    enum Outcome: Equatable {
        case putBack
        /// Something is at the old place now: it is left alone, and so is the Trash.
        case inTheWay
        /// The Trash was emptied, or the item was taken out of it.
        case gone
        /// What Floe added was deleted.
        case deleted
        /// It was not there any more: the user deleted it first.
        case alreadyDeleted
        /// The note went to the Trash. With the receipt of that move, which can put it back.
        case trashed(Receipt)
        /// The note is not as Floe wrote it, so it stays.
        case changed
        /// The note is not where Floe wrote it.
        case missing
        case failed(String)
        case notUndoable
    }

    /// `delete` answers false when what Floe added is no longer there. Without it, such a receipt cannot be undone.
    static func undo(
        _ receipt: Receipt,
        fileManager: FileManager = .default,
        delete: ((String) throws -> Bool)? = nil,
        trash: (URL) throws -> Receipt = { try ReceiptStore.trash($0) }
    ) -> Outcome {
        guard receipt.canUndo else { return .notUndoable }
        if receipt.kind == .note {
            return discard(receipt, fileManager: fileManager, trash: trash)
        }
        if let identifier = receipt.identifier {
            guard let delete else { return .notUndoable }
            do {
                return try delete(identifier) ? .deleted : .alreadyDeleted
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        guard let original = receipt.original, let trashed = receipt.trashed else { return .notUndoable }
        guard fileManager.fileExists(atPath: trashed) else { return .gone }
        guard !fileManager.fileExists(atPath: original) else { return .inTheWay }
        do {
            try fileManager.createDirectory(atPath: (original as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try fileManager.moveItem(atPath: trashed, toPath: original)
            return .putBack
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Moves a note Floe wrote to the Trash, unless its size or date say it was changed since.
    private static func discard(_ receipt: Receipt, fileManager: FileManager, trash: (URL) throws -> Receipt) -> Outcome {
        guard let path = receipt.original, let size = receipt.size, let modified = receipt.modified else { return .notUndoable }
        guard fileManager.fileExists(atPath: path) else { return .missing }
        let current = Receipt.note(URL(fileURLWithPath: path), fileManager: fileManager)
        // A date goes through the receipts' file as a number, which may not keep its last digit.
        guard current.size == size, let changed = current.modified, abs(changed.timeIntervalSince(modified)) < 0.001 else { return .changed }
        do {
            return try .trashed(trash(URL(fileURLWithPath: path)))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func message(for outcome: Outcome, subject: String, kind: Receipt.Kind = .trash) -> String {
        switch outcome {
        case .putBack: String(localized: "Put \(subject) back", bundle: .floe, comment: "The placeholder is a file name.")
        case .inTheWay: String(localized: "Something else is where \(subject) was, so it stays in the Trash", bundle: .floe, comment: "The placeholder is a file name.")
        case .gone: String(localized: "\(subject) is no longer in the Trash", bundle: .floe, comment: "The placeholder is a file name.")
        case .deleted: deleted(subject, kind: kind)
        case .alreadyDeleted: alreadyDeleted(subject, kind: kind)
        case .trashed: String(localized: "Moved \(subject) to the Trash", bundle: .floe, comment: "A receipt. The placeholder is a file name.")
        case .changed: String(localized: "\(subject) was changed after Floe wrote it, so it stays where it is", bundle: .floe, comment: "The placeholder is the name of a note's file.")
        case .missing: String(localized: "\(subject) is no longer where Floe wrote it", bundle: .floe, comment: "The placeholder is the name of a note's file.")
        case let .failed(reason): reason
        case .notUndoable: String(localized: "This cannot be undone.", bundle: .floe)
        }
    }

    private static func deleted(_ subject: String, kind: Receipt.Kind) -> String {
        switch kind {
        case .event: String(localized: "Deleted the event \(subject)", bundle: .floe, comment: "The placeholder is what the event is called, such as lunch with Ana.")
        case .checkpoint: String(localized: "Deleted the checkpoint \(subject)", bundle: .floe, comment: "The placeholder is the name the user gave a checkpoint.")
        default: String(localized: "Deleted the reminder \(subject)", bundle: .floe, comment: "The placeholder is what the reminder is about, such as call mom.")
        }
    }

    private static func alreadyDeleted(_ subject: String, kind: Receipt.Kind) -> String {
        switch kind {
        case .event: String(localized: "The event \(subject) was already deleted", bundle: .floe, comment: "The placeholder is what the event is called, such as lunch with Ana.")
        case .checkpoint: String(localized: "The checkpoint \(subject) was already deleted", bundle: .floe, comment: "The placeholder is the name the user gave a checkpoint.")
        default: String(localized: "The reminder \(subject) was already deleted", bundle: .floe, comment: "The placeholder is what the reminder is about, such as call mom.")
        }
    }
}

/// The receipts, newest first, in a file. Read from the file each time: the settings window is another process
/// and writes one when it removes an extension.
final nonisolated class ReceiptStore: Sendable {
    static let shared = ReceiptStore()
    static let limit = 200

    private let file: URL

    init(file: URL = Paths.support.appendingPathComponent("Receipts.json")) {
        self.file = file
    }

    var all: [Receipt] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Receipt].self, from: $0) } ?? []
    }

    func add(_ receipt: Receipt) {
        write(Array(([receipt] + all).prefix(Self.limit)))
    }

    func markUndone(_ id: UUID, at date: Date = Date()) {
        write(all.map { receipt in
            var receipt = receipt
            if receipt.id == id {
                receipt.undone = date
            }
            return receipt
        })
    }

    func forget() {
        try? FileManager.default.removeItem(at: file)
    }

    private func write(_ receipts: [Receipt]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(receipts).write(to: file, options: .atomic)
    }

    /// Moves something to the Trash and answers with the receipt that can put it back.
    static func trash(_ url: URL, as kind: Receipt.Kind = .trash, subject: String? = nil, now: Date = Date()) throws -> Receipt {
        var inTrash: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
        let name = subject ?? FileManager.default.displayName(atPath: url.path)
        let place = (url.path as NSString).abbreviatingWithTildeInPath
        return Receipt(date: now, kind: kind, subject: name, detail: place, original: url.path, trashed: inTrash?.path)
    }
}
