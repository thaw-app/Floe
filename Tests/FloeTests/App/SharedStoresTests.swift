//
//  SharedStoresTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The save hooks are the shared stores' own, so each test puts back the ones it found.
@MainActor
@Suite(.serialized)
struct SharedStoresTests {
    private func withSavedHooks(_ body: () throws -> Void) rethrows {
        let snippets = SnippetStore.shared.onSaved
        let quicklinks = QuicklinkStore.shared.onSaved
        let preferences = PreferenceStore.onSaved
        defer {
            SnippetStore.shared.onSaved = snippets
            QuicklinkStore.shared.onSaved = quicklinks
            PreferenceStore.onSaved = preferences
        }
        try body()
    }

    @Test func eachStoreSaysWhichItIsWhenItSaves() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        withSavedHooks {
            var sent: [LinkMessage] = []
            SharedStores.announceSaves(settings: settings) { sent.append($0) }
            settings.onSaved?()
            SnippetStore.shared.onSaved?()
            QuicklinkStore.shared.onSaved?()
            PreferenceStore.onSaved()
            #expect(sent.map(\.kind) == [.settingsChanged, .storeChanged, .storeChanged, .storeChanged])
            #expect(sent.compactMap(\.store) == [.snippets, .quicklinks, .preferences])
        }
    }

    @Test func aProcessThatActsOnPreferencesItselfIsNotSentThem() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        withSavedHooks {
            var sent: [LinkMessage] = []
            var acted = 0
            SharedStores.announceSaves(settings: settings, preferencesSaved: { acted += 1 }, send: { sent.append($0) })
            PreferenceStore.onSaved()
            #expect(acted == 1)
            #expect(sent.isEmpty)
        }
    }

    @Test func preferencesAreReadAgainWhereTheyAreUsedAndNoStoreReadsNothing() {
        var preferences = 0
        SharedStores.reload(.preferences) { preferences += 1 }
        SharedStores.reload(nil) { preferences += 1 }
        #expect(preferences == 1)
    }
}
