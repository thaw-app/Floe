//
//  SettingsWindow.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// The settings window. Only the settings process makes one (see SettingsMode.swift).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let catalog: CatalogStore
    private let stores: SettingsStores
    let selection = SettingsSelection()
    /// Called once the window has closed.
    var onClose: () -> Void = { /* set by the settings process */ }

    /// Room for the sidebar with its search field and a readable pane.
    private static let minimumSize = NSSize(width: 720, height: 460)

    init(catalog: CatalogStore, stores: SettingsStores) {
        self.catalog = catalog
        self.stores = stores
    }

    var isOpen: Bool {
        window != nil
    }

    func show(page: SettingsPage? = nil) {
        selection.page = page ?? selection.page
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            // Kept for the Window menu and VoiceOver; the titlebar shows no title, each page names itself.
            window.title = String(localized: "Floe Settings", bundle: .floe)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = Self.minimumSize
            // As Thaw's windows: not a workspace, so the green button zooms, and nothing worth restoring.
            window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenNone])
            window.isRestorable = false
            let content = NSHostingView(rootView: SettingsView(catalog: catalog, stores: stores, selection: selection).openingLinksInTheChosenBrowser())
            // Nothing bridged, so the window has no toolbar and each page names itself. Removing the
            // toolbar's items in SwiftUI instead shrinks the sidebar to 144 points.
            content.sceneBridgingOptions = []
            window.contentView = content
            window.center()
            window.delegate = self
            self.window = window
        }
        UpdatesManager.settingsWillShow()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // The system may hold back activation for a process the user did not start, and the window with it.
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        window = nil
        // A turn later, so the window finishes closing before the process may end.
        DispatchQueue.main.async { [onClose] in onClose() }
    }
}

nonisolated enum SettingsPage: Hashable {
    case general
    case commands
    case applications
    case ai
    case sync
    case quicklinks
    case fallbacks
    case snippets
    case extensionStore
    case appearance
    case privacy
    case about
    case extensionPage(String)

    private static let extensionPrefix = "extension:"
    private static let fixed: [String: SettingsPage] = [
        "general": .general,
        "commands": .commands,
        "applications": .applications,
        "ai": .ai,
        "sync": .sync,
        "quicklinks": .quicklinks,
        "fallbacks": .fallbacks,
        "snippets": .snippets,
        "store": .extensionStore,
        "appearance": .appearance,
        "privacy": .privacy,
        "about": .about,
    ]

    /// The page's name on the command line and between the two processes.
    var id: String {
        if case let .extensionPage(name) = self {
            return Self.extensionPrefix + name
        }
        return Self.fixed.first { $0.value == self }?.key ?? "general"
    }

    /// Nil for a name that is no page, which leaves the window on the page it has.
    init?(id: String) {
        if id.hasPrefix(Self.extensionPrefix), id.count > Self.extensionPrefix.count {
            self = .extensionPage(String(id.dropFirst(Self.extensionPrefix.count)))
        } else if let page = Self.fixed[id] {
            self = page
        } else {
            return nil
        }
    }
}

final class SettingsSelection: ObservableObject {
    @Published var page: SettingsPage = .general
}
