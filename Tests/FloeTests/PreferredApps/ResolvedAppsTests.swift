//
//  ResolvedAppsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct ResolvedAppsTests {
    /// A lookup that counts how often it was asked, and finds nothing.
    private func countingLookup(_ asked: @escaping () -> Void) -> AppLookup {
        AppLookup(url: { _ in asked(); return nil }, plainTextApp: { nil }, exists: { _ in false }, bundleIdentifier: { _ in nil })
    }

    @Test func theAppsAreLookedUpOnceUntilAChoiceOrTheLookupChanges() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        let resolved = ResolvedApps(settings: settings)
        resolved.followChoices()
        var asked = 0
        resolved.lookup = countingLookup { asked += 1 }

        _ = resolved.apps
        let first = asked
        #expect(first > 0)
        _ = resolved.apps
        _ = resolved.clipboardDestination
        let afterCache = asked
        _ = resolved.apps
        #expect(asked == afterCache, "kept until something changes")

        settings.terminalApp = AppChoice(bundleIdentifier: "com.example.terminal", path: "/Applications/Terminal Example.app")
        _ = resolved.apps
        #expect(asked > afterCache, "a changed choice is looked up again")

        let beforeNewLookup = asked
        resolved.lookup = countingLookup { asked += 1 }
        _ = resolved.apps
        #expect(asked > beforeNewLookup, "so is a new lookup")
    }
}
