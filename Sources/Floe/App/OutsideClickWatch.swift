//
//  OutsideClickWatch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Tells the launcher about a click in another app while it is open.
///
/// The launcher's panel takes the keyboard without making Floe the active app. A click in a window of the app that is
/// already active never takes the keyboard back from it, so the panel is not told it lost focus. Watching other apps'
/// clicks needs no permission.
final class OutsideClickWatch {
    typealias Install = (@escaping () -> Void) -> Any?

    private let install: Install
    private let remove: (Any) -> Void
    private var monitor: Any?

    var isWatching: Bool {
        monitor != nil
    }

    init(
        install: @escaping Install = { onClick in
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in onClick() }
        },
        remove: @escaping (Any) -> Void = NSEvent.removeMonitor
    ) {
        self.install = install
        self.remove = remove
    }

    /// Calls onClick for each click in another app until stop. Starting again replaces the earlier watch.
    func start(_ onClick: @escaping () -> Void) {
        stop()
        monitor = install(onClick)
    }

    func stop() {
        guard let monitor else { return }
        remove(monitor)
        self.monitor = nil
    }
}
