//
//  ClipboardPasteboard.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices

extension ClipboardHistoryStore {
    /// Writes an entry back to a pasteboard, with its formatting when it has any and with the mark that
    /// tells Floe's own watcher which entry it is. False when the pasteboard did not take it.
    @discardableResult
    static func writeToPasteboard(_ entry: ClipboardEntry, board: NSPasteboard = .general, directory: URL = ClipboardHistoryStore.directory) -> Bool {
        let before = board.changeCount
        board.clearContents()
        let written: Bool
        switch entry.kind {
        case .text, .link:
            guard let text = entry.text else { return false }
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            for (type, name) in entry.formats ?? [:] {
                if let data = storedFile(name, in: directory) {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
            }
            item.setString(entry.id.uuidString, forType: ClipboardCapture.ownEntryType)
            written = board.writeObjects([item])
        case .file:
            let urls = (entry.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            written = !urls.isEmpty && board.writeObjects(urls) && mark(board, as: entry)
        case .image:
            guard let name = entry.imageFile, let data = storedFile(name, in: directory), let image = NSImage(data: data)
            else { return false }
            written = board.writeObjects([image]) && mark(board, as: entry)
        }
        // The count moves when the pasteboard takes the entry: pasting before it has gives the copy before this one.
        return written && board.changeCount != before
    }

    /// A file the history names, read only when it is a plain file right inside the clipboard folder. The names
    /// come from history.json, which anyone who can write the folder can edit, so a link or a path that leaves the
    /// folder is not followed.
    static nonisolated func storedFile(_ name: String, in directory: URL) -> Data? {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
        let folder = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folder >= 0 else { return nil }
        defer { close(folder) }
        let file = openat(folder, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
        var status = stat()
        guard fstat(file, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return nil }
        return try? handle.readToEnd() ?? Data()
    }

    private static func mark(_ board: NSPasteboard, as entry: ClipboardEntry) -> Bool {
        board.addTypes([ClipboardCapture.ownEntryType], owner: nil)
        return board.setString(entry.id.uuidString, forType: ClipboardCapture.ownEntryType)
    }

    /// Whether Return pastes straight into the frontmost app: needs Accessibility.
    static var canPasteDirectly: Bool {
        AXIsProcessTrusted()
    }

    /// Presses Command-V, so the just-copied entry lands in the frontmost app.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Presses Command-V once Floe is out of the way: the app in front, not Floe, has to be the one that reads the key.
    /// Never sooner than 0.15 s, the pause Floe used before, and no later than a second.
    static func pasteWhenClear(
        isClear: @escaping () -> Bool = { NSApp.keyWindow == nil && NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier },
        press: @escaping () -> Void = { simulatePaste() }
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            var waits = 0
            while !isClear(), waits < 17 {
                try? await Task.sleep(for: .milliseconds(50))
                waits += 1
            }
            press()
        }
    }
}
