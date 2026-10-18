//
//  EmojiRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Emoji the search found: Return pastes one into the app in front, Command-Return only copies it.
final class EmojiRows {
    var host = RowHost()
    /// Counts a use, so the emoji comes up sooner next time.
    var recordUse: (String) -> Void = { _ in }
    /// Where an emoji is copied to. Tests replace it, so they leave the clipboard alone.
    var pasteboard = NSPasteboard.general
    /// Whether Command-V may be pressed for the user, and pressing it. Tests replace both, so they press nothing.
    var canPaste: () -> Bool = { AXIsProcessTrusted() }
    var pressPaste: () -> Void = { ClipboardHistoryStore.simulatePaste() }

    /// Copies an emoji without pasting.
    func copy(_ entry: EmojiResult) {
        recordUse(entry.id)
        pasteboard.copy(entry.character)
        host.showHUD(String(localized: "Copied \(entry.character)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
    }

    /// Pastes an emoji into the app in front: onto the clipboard plus Command-V once the panel is gone,
    /// when Accessibility allows it; otherwise the copy and a HUD that says so.
    func paste(_ entry: EmojiResult) {
        recordUse(entry.id)
        pasteboard.copy(entry.character)
        guard canPaste() else {
            host.showHUD(String(localized: "Copied", bundle: .floe, comment: "Shown briefly after something was put on the clipboard."))
            return
        }
        host.leave()
        // Pressed once the panel is gone, so the keystroke lands in the app the user came from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [pressPaste] in
            pressPaste()
        }
    }
}

extension EmojiRows: RowOwner {
    func returnTitle(for _: RootItem) -> String? {
        nil
    }

    func open(_ item: RootItem, flags: NSEvent.ModifierFlags) -> Bool {
        guard case let .emoji(entry) = item else { return false }
        if flags == .command {
            copy(entry)
        } else {
            paste(entry)
        }
        return true
    }
}
