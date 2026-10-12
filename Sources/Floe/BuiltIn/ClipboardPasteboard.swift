//
//  ClipboardPasteboard.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices

extension ClipboardHistoryStore {
    /// Writes an entry back to the general pasteboard.
    @discardableResult
    static func writeToPasteboard(_ entry: ClipboardEntry) -> Bool {
        let board = NSPasteboard.general
        board.clearContents()
        switch entry.kind {
        case .text, .link:
            guard let text = entry.text else { return false }
            return board.setString(text, forType: .string)
        case .file:
            let urls = (entry.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            board.writeObjects(urls)
            return true
        case .image:
            guard let name = entry.imageFile,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let image = NSImage(data: data)
            else { return false }
            board.writeObjects([image])
            return true
        }
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
}
