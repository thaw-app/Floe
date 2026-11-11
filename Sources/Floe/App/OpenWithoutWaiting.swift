//
//  OpenWithoutWaiting.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

extension NSWorkspace {
    /// Opens a file, an app or a link and returns at once. `open(_:)` waits for the system's answer,
    /// which held the main thread for 300 ms while an app started.
    nonisolated func openWithoutWaiting(_ url: URL) {
        open(url, configuration: OpenConfiguration()) { _, _ in
            // Nothing to wait for: the open was asked for, and the answer changes nothing here.
        }
    }

    /// A file's or an app's icon at the size a menu row draws it.
    func smallIcon(forFile path: String) -> NSImage {
        let icon = icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
