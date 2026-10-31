//
//  FloatingNoteWindow.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// A panel over every app, on every Space and beside full-screen apps. It takes the keyboard without making
/// Floe the active app, as the launcher does, so the app in front stays in front.
final class FloatingNotePanel: NSPanel {
    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // A panel hides when its app stops being active; this one stays while the user works in another app.
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        // An empty toolbar makes the title bar tall enough for the note's name, with the close button centred in it.
        toolbar = NSToolbar()
        toolbarStyle = .unifiedCompact
        title = String(localized: "Floating Note", bundle: .floe, comment: "The command, and the window, that keep a note on top of other apps.")
    }

    override var canBecomeKey: Bool {
        true
    }
}

/// Owns the floating note's window in the process that shows the launcher. One window, one note at a time.
final class FloatingNoteWindowController: NSObject, NSWindowDelegate {
    /// Where AppKit keeps the window's frame between launches.
    static let frameName = "FloatingNote"

    private let settings: AppSettings
    private let record: (Receipt) -> Void
    private var panel: FloatingNotePanel?
    private var model: FloatingNoteModel?
    private var keyMonitor: Any?

    init(
        settings: AppSettings,
        record: @escaping (Receipt) -> Void = { _ in
            // No receipts kept.
        }
    ) {
        self.settings = settings
        self.record = record
    }

    var isOpen: Bool {
        panel?.isVisible == true
    }

    /// Opens the window on the notes app's notes, or brings it forward when it is open.
    func show() {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let store = FloatingNoteStores.store(for: settings.notesApp, folder: settings.notesFolder, template: settings.notesURLTemplate, record: record)
        let model = FloatingNoteModel(store: store, environment: environment())
        model.close = { [weak self] in self?.dismiss() }
        self.model = model
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: FloatingNoteView(model: model, titleBarHeight: panel.frame.height - panel.contentLayoutRect.height).thawTheme(.floe))
        panel.makeKeyAndOrderFront(nil)
        watchKeys()
        model.start()
    }

    /// Saves the note and calls back once it is saved, or after a few seconds when the store does not answer.
    /// The process waits on it before it ends.
    func finish(then done: @escaping () -> Void) {
        guard let model else {
            done()
            return
        }
        waitAtMost(.seconds(5), for: { _ = await model.commit() }, then: done)
    }

    private func makePanel() -> FloatingNotePanel {
        let panel = FloatingNotePanel()
        panel.delegate = self
        if !panel.setFrameUsingName(Self.frameName) {
            panel.center()
        }
        panel.setFrameAutosaveName(Self.frameName)
        return panel
    }

    private func environment() -> FloatingNoteModel.Environment {
        var environment = FloatingNoteModel.Environment()
        environment.send = { [settings] action, text, done in
            Notes.perform(action, text: text, app: settings.notesApp, template: settings.notesURLTemplate, completion: done)
        }
        return environment
    }

    /// The window's own keys come first, before the text and the main menu see them.
    private func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, let model = self.model else { return event }
            // While an input method is composing, Return and Escape belong to it.
            if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true {
                return event
            }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            return model.handleKey(event, flags) ? nil : event
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        model = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// The close button and Close Window save first: the window goes once the note is saved.
    func windowShouldClose(_: NSWindow) -> Bool {
        model?.requestClose()
        return model == nil
    }
}
