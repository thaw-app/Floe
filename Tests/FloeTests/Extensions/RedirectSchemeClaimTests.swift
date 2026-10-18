//
//  RedirectSchemeClaimTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Raycast's return addresses, held while a sign-in waits, with a handler table of the test's own.
@MainActor
struct RedirectSchemeClaimTests {
    private final class Table {
        var handlers: [String: URL] = [:]
        var changes: [String] = []
    }

    private let floe = URL(fileURLWithPath: "/Applications/Floe.app")
    private let raycast = URL(fileURLWithPath: "/Applications/Raycast.app")
    private let table = Table()
    private let defaults: UserDefaults = MemoryDefaults()

    private func claim() -> RedirectSchemeClaim {
        let table = table
        let handlers = RedirectSchemeClaim.Handlers(
            current: { table.handlers[$0] },
            set: { app, scheme in
                table.handlers[scheme] = app
                table.changes.append("\(scheme) → \(app.lastPathComponent)")
            }
        )
        return RedirectSchemeClaim(handlers: handlers, defaults: defaults, floe: floe)
    }

    @Test func theSchemeIsReadFromTheAuthorizationURLsRedirect() throws {
        let app = try #require(URL(string: "https://accounts.google.com/auth?client_id=c&redirect_uri=com.raycast%3A%2Foauth%3Fpackage_name%3DExtension"))
        let web = try #require(URL(string: "https://github.com/login?redirect_uri=https%3A%2F%2Fraycast.com%2Fredirect"))
        #expect(RedirectSchemeClaim.scheme(returningFrom: app) == "com.raycast")
        #expect(RedirectSchemeClaim.scheme(returningFrom: web) == nil)
    }

    @Test func raycastGetsItsSchemeBackWhenTheLastSignInEnds() async {
        table.handlers["raycast"] = raycast
        let claim = claim()
        await claim.claim("raycast")
        await claim.claim("raycast")
        #expect(table.handlers["raycast"] == floe)

        await claim.release("raycast")
        #expect(table.handlers["raycast"] == floe, "another sign-in still waits")
        await claim.release("raycast")
        #expect(table.changes == ["raycast → Floe.app", "raycast → Raycast.app"])
    }

    @Test func withoutRaycastNothingChanges() async {
        table.handlers["com.raycast"] = floe
        let claim = claim()
        await claim.claim("com.raycast")
        await claim.release("com.raycast")
        #expect(table.changes.isEmpty)
    }

    @Test func aSignInCutShortByACrashGivesTheSchemeBackOnTheNextStart() async {
        table.handlers["raycast"] = raycast
        await claim().claim("raycast")

        await claim().restoreAfterCrash()
        #expect(table.handlers["raycast"] == raycast)
        await claim().restoreAfterCrash()
        #expect(table.changes.count == 2, "given back once")
    }
}
