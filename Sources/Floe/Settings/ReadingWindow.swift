//
//  ReadingWindow.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// A window one of the reading pages opens in. It is built when asked for and let go when closed.
@MainActor
final class ReadingWindow {
    static let releaseNotes = ReadingWindow(title: String(localized: "What’s New", bundle: .floe)) {
        AnyView(WhatsNewView(info: .floe, strings: .floe))
    }

    static let acknowledgements = ReadingWindow(title: String(localized: "Acknowledgements", bundle: .floe)) {
        AnyView(AcknowledgementsView(appName: AppInfo.displayName, strings: .floe, content: .floe()))
    }

    /// Called after one of them has closed. The settings process sets it: it stays alive while one is open.
    static var onClose: (() -> Void)?

    static var isAnyOpen: Bool {
        releaseNotes.isOpen || acknowledgements.isOpen
    }

    private let title: String
    private let content: () -> AnyView
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init(title: String, content: @escaping () -> AnyView) {
        self.title = title
        self.content = content
    }

    var isOpen: Bool {
        window != nil
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.isReleasedWhenClosed = false
        created.title = title
        created.contentView = NSHostingView(rootView: content().buttonBorderShape(.capsule).openingLinksInTheChosenBrowser().thawTheme(.floe))
        created.center()
        closeObserver = NotificationCenter.default.addMainObserver(forName: NSWindow.willCloseNotification, object: created) { [weak self] in
            self?.closed()
        }
        window = created
        NSApp.activate()
        created.makeKeyAndOrderFront(nil)
    }

    private func closed() {
        window = nil
        closeObserver.map(NotificationCenter.default.removeObserver)
        closeObserver = nil
        Self.onClose?()
    }
}
