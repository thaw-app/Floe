//
//  ThawUIWords+Hotkeys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

nonisolated extension HotkeyRecorderStrings {
    static let floe = HotkeyRecorderStrings(
        typeShortcut: .floe("Type Shortcut"),
        recordShortcut: .floe("Record Shortcut"),
        cancel: LocalizedStringResource("Cancel", bundle: .floe, comment: "A button that stops what is under way, such as recording a keyboard shortcut."),
        // Its own key: the glass style named Clear is another word in most languages.
        clear: LocalizedStringResource("Clear Shortcut", defaultValue: "Clear", bundle: .floe, comment: "Spoken for the button that removes a keyboard shortcut."),
        record: LocalizedStringResource("Record", bundle: .floe, comment: "Spoken for the button that starts recording a keyboard shortcut."),
        spaceKey: LocalizedStringResource("Space", bundle: .floe, comment: "The name of the space bar in a keyboard shortcut."),
        reservedTitle: .floe("macOS already uses this shortcut"),
        reservedMessage: .floe("Record a different one, or turn this one off in System Settings → Keyboard → Keyboard Shortcuts."),
        chooseAnother: .floe("Choose Another")
    )
}

extension HotkeyRecorder {
    /// A recorder at a fixed width, so every one in a list lines up whatever its label, and a row with a description
    /// beside it still has room for one.
    init(
        keyCombination: Binding<KeyCombination?>,
        onRecordingChange: @escaping (Bool) -> Void = { _ in
            // Nothing to suspend.
        },
        @ViewBuilder label: () -> Label
    ) {
        self.init(keyCombination: keyCombination, strings: .floe, width: 160, onRecordingChange: onRecordingChange, label: label)
    }
}

extension KeyCode {
    /// A short label for the key, with Floe's word for the space bar.
    var stringValue: String {
        stringValue(spaceName: String(localized: HotkeyRecorderStrings.floe.spaceKey))
    }
}

extension KeyCombination {
    /// The combination as a line of text, with Floe's word for the space bar.
    var displayValue: String {
        displayValue(spaceName: String(localized: HotkeyRecorderStrings.floe.spaceKey))
    }
}
