//
//  ClosureMenuItem.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3's LayoutBarItemMenu.

import AppKit

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    /// AppKit's initializers are nonisolated, and so must be what stands in for them here.
    @available(*, unavailable)
    override nonisolated init(title _: String, action _: Selector?, keyEquivalent _: String) {
        fatalError("init(title:action:keyEquivalent:) has not been implemented")
    }

    @available(*, unavailable)
    required nonisolated init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}
