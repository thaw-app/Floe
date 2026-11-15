//
//  SnippetTyping.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// The last keys typed in another app, as far as they could still end in a snippet's keyword. It forgets them
/// whenever the caret may have moved, so the Backspaces of an expansion only ever remove what was just typed.
nonisolated struct KeywordBuffer: Equatable {
    enum Key: Equatable {
        case typed(String)
        case backspace
        /// A key that moves the caret or acts on the app, after which what was typed before no longer counts.
        case wordEnd
    }

    static let maxLength = 32
    static let backspaceKeyCode = CGKeyCode(kVK_Delete)
    static let wordEndKeyCodes = Set([
        kVK_Return, kVK_Tab, kVK_Escape, kVK_ANSI_KeypadEnter, kVK_ForwardDelete, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow,
    ].map { CGKeyCode($0) })
    /// Function keys type characters from U+F700 up.
    private static let functionKeyCharacters: ClosedRange<UInt32> = 0xF700 ... 0xF8FF

    private(set) var text = ""

    /// What a key press means here. Nil for a key that typed nothing, such as the first half of an accent.
    static func key(code: CGKeyCode, flags: CGEventFlags, characters: String?) -> Key? {
        // Modifier shortcuts act on the app, they are not typed text.
        if !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) || wordEndKeyCodes.contains(code) {
            return .wordEnd
        }
        if code == backspaceKeyCode {
            return .backspace
        }
        guard let characters, !characters.isEmpty else { return nil }
        let isText = characters.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !functionKeyCharacters.contains($0.value)
        }
        return isText ? .typed(characters) : .wordEnd
    }

    /// Takes a key and returns the text to look for a keyword in, which is only after a typed character.
    mutating func take(_ key: Key) -> String? {
        switch key {
        case let .typed(characters):
            text = String((text + characters).suffix(Self.maxLength))
            return text
        case .backspace:
            if !text.isEmpty {
                text.removeLast()
            }
            return nil
        case .wordEnd:
            text = ""
            return nil
        }
    }

    mutating func clear() {
        text = ""
    }
}

/// Lends the pasteboard to an expansion, which pastes with Command-V, and puts back what was there.
enum SnippetPasteboard {
    /// The nspasteboard.org marker for content put back by a program, which clipboard managers already hold.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    struct Loan {
        let saved: SavedPasteboard.Snapshot
        /// The pasteboard's change count right after the snippet was written.
        let changeCount: Int
    }

    /// Writes the snippet, concealed so no clipboard history keeps it. A loan not given back yet keeps its saved
    /// content as long as nothing else wrote since, because the pasteboard then holds the earlier snippet.
    static func lend(_ text: String, to pasteboard: NSPasteboard = .general, after earlier: Loan?) -> Loan {
        let saved = if let earlier, earlier.changeCount == pasteboard.changeCount {
            earlier.saved
        } else {
            SavedPasteboard.capture(pasteboard)
        }
        PasteboardContent.write(text: text, html: nil, file: nil, concealed: true, to: pasteboard)
        return Loan(saved: saved, changeCount: pasteboard.changeCount)
    }

    /// Puts back what was there, unless something wrote to the pasteboard since the snippet.
    @discardableResult
    static func giveBack(_ loan: Loan, to pasteboard: NSPasteboard = .general) -> Bool {
        guard pasteboard.changeCount == loan.changeCount else { return false }
        loan.saved.restore(to: pasteboard)
        if !loan.saved.items.isEmpty {
            // Clipboard history already has this content from when it was copied, or chose not to keep it.
            pasteboard.setString("", forType: transientType)
        }
        return true
    }
}
