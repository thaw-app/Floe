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
        let lease = PanelWork.begin()
        open(url, configuration: OpenConfiguration()) { _, _ in
            withExtendedLifetime(lease) {
                // Only completion matters here: retain the lease until NSWorkspace finishes opening.
            }
        }
    }
}
