//
//  Model+Clipboard.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// Where the Clipboard History command goes: Floe's own view, which is `ClipboardHistoryModel`, or the app chosen to keep it.
extension LauncherModel {
    /// Where the Clipboard History command goes now, resolved once per change
    /// (see LauncherModel.resolvedClipboardDestination).
    var clipboardDestination: ClipboardDestination {
        resolvedClipboardDestination
    }

    /// Switches the panel to the clipboard history, or opens the app chosen to keep it.
    func openClipboardHistory() {
        let destination = clipboardDestination
        guard destination == .floe else {
            openClipboardApp(destination)
            return
        }
        if let session {
            end(session)
        }
        setup = nil
        isSearchingMenuBar = false
        isShowingClipboardHistory = true
        clipboardHistory.query = ""
        clipboardHistory.selection = 0
        showPanel()
        focusToken += 1
    }

    /// Hands the command to the chosen app. One that cannot be opened is named in the HUD.
    private func openClipboardApp(_ destination: ClipboardDestination) {
        hidePanel()
        reset()
        switch destination {
        case .floe: break
        case let .app(app): clipboardOpener.app(app.url)
        case let .link(url, app): clipboardOpener.link(url, app?.url)
        case let .unavailable(_, message): showHUD(message)
        }
    }

    /// Follows the clipboard role as Settings changes it: Floe's history view closes, and the row is drawn again.
    func followClipboardRole() -> AnyCancellable {
        settings.$clipboardHandler.removeDuplicates()
            .combineLatest(settings.$clipboardApp.removeDuplicates(), settings.$clipboardURL.removeDuplicates())
            .dropFirst()
            // After the publisher's willSet, so the new value is the one read.
            .sink { [weak self] handler, _, _ in
                DispatchQueue.main.async {
                    if handler != .floe {
                        self?.isShowingClipboardHistory = false
                    }
                    self?.refresh()
                }
            }
    }

    func closeClipboardHistory() {
        isShowingClipboardHistory = false
        focusToken += 1
    }
}
