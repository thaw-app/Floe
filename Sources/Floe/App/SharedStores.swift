//
//  SharedStores.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The stores every process writes to disk: settings, snippets, quicklinks and extension preferences.
/// A process that saves one says so; the others read it again. Each process wires both sides here.
enum SharedStores {
    /// Has each store send its message when it saved. A process that acts on saved preferences itself passes
    /// preferencesSaved instead of having them sent.
    static func announceSaves(
        settings: AppSettings,
        preferencesSaved: (() -> Void)? = nil,
        send: @escaping (LinkMessage) -> Void
    ) {
        settings.onSaved = { send(.settingsChanged) }
        SnippetStore.shared.onSaved = { send(.storeChanged(.snippets)) }
        QuicklinkStore.shared.onSaved = { send(.storeChanged(.quicklinks)) }
        PreferenceStore.onSaved = preferencesSaved ?? { send(.storeChanged(.preferences)) }
    }

    /// Reads every store again, for when another process may have saved one without saying so.
    static func reloadAll(settings: AppSettings) {
        settings.reload()
        reload(.snippets)
        reload(.quicklinks)
    }

    /// Reads again the store another process saved. Preferences are read where they are used, so a process
    /// that keeps something made from them passes what to do.
    static func reload(_ store: LinkStore?, preferences: () -> Void = {}) {
        switch store {
        case .snippets: SnippetStore.shared.reload()
        case .quicklinks: QuicklinkStore.shared.reload()
        case .preferences: preferences()
        case nil: break
        }
    }
}
