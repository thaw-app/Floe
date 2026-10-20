//
//  QuickLookPresenter.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Quartz

/// Shows one file in the system's Quick Look panel, for a row that stands for a file.
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()
    private(set) var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate()
        if panel.dataSource === self {
            panel.reloadData()
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// `Action.ToggleQuickLook`: closes the preview of this file, or shows it.
    func toggle(_ url: URL) {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible, self.url == url {
            panel.orderOut(nil)
        } else {
            show(url)
        }
    }

    func numberOfPreviewItems(in _: QLPreviewPanel?) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_: QLPreviewPanel?, previewItemAt _: Int) -> QLPreviewItem? {
        url as NSURL?
    }

    /// Space closes the preview it opened, as in Finder.
    func previewPanel(_ panel: QLPreviewPanel?, handle event: NSEvent?) -> Bool {
        guard event?.type == .keyDown, event?.keyCode == 49 else { return false }
        panel?.orderOut(nil)
        return true
    }
}

/// The panel asks the responder chain who controls it, and the app's delegate is the end of that chain.
/// AppKit declares the three calls without an actor and makes them on the main thread.
extension AppDelegate {
    override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel?) -> Bool {
        QuickLookPresenter.accepts()
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel?) {
        QuickLookPresenter.begin(panel)
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel?) {
        QuickLookPresenter.end(panel)
    }
}

extension QuickLookPresenter {
    nonisolated static func accepts() -> Bool {
        MainActor.assumeIsolated { shared.url != nil }
    }

    nonisolated static func begin(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = shared
            panel?.delegate = shared
        }
    }

    nonisolated static func end(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = nil
            panel?.delegate = nil
        }
    }
}
