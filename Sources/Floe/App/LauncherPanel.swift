//
//  LauncherPanel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

final class LauncherPanel: NSPanel {
    /// The floating, borderless, see-through window the launcher and the picker both draw their glass in.
    convenience init(size: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        // See LauncherView.margin: the window's own shadow is square.
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool {
        true
    }
}
