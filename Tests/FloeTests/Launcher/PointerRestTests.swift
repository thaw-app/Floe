//
//  PointerRestTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import SwiftUI
import Testing

struct PointerRestTests {
    @Test func aPointerThatNeverRestedMarksRows() {
        #expect(PointerRest().hasMoved(to: .zero))
    }

    @Test func aRestingPointerMarksNoRowUntilItMovesMoreThanTheSlack() {
        let rest = PointerRest()
        rest.rest(at: CGPoint(x: 100, y: 100))
        #expect(!rest.hasMoved(to: CGPoint(x: 100, y: 100)), "a row slid under the pointer")
        #expect(!rest.hasMoved(to: CGPoint(x: 101, y: 101)))
        #expect(rest.hasMoved(to: CGPoint(x: 103, y: 100)))
        #expect(rest.hasMoved(to: CGPoint(x: 100, y: 100)), "once moved, it stays moved until the next rest")

        rest.rest(at: CGPoint(x: 100, y: 100))
        #expect(!rest.hasMoved(to: CGPoint(x: 100, y: 100)))
    }
}

struct ReturnRefusalTests {
    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func returnWithNoResultIsRefusedUntilTheQueryChanges() throws {
        let defaults = MemoryDefaults()
        let model = LauncherModel(
            settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []),
            scopes: [ClipboardSearchScope(entries: { [] })], sources: []
        )
        model.query = "clipboard zzzz"
        model.typing.flush()
        try #require(model.results.isEmpty, "a scope with nothing in it offers no row")

        #expect(try model.handleKey(key(36)))
        #expect(model.refusal.isShown)
        #expect(model.refusal.count == 1)
        #expect(try model.handleKey(key(36)))
        #expect(model.refusal.count == 2, "each refusal shakes again")

        model.query = "clipboard zzz"
        #expect(!model.refusal.isShown)
        #expect(model.refusal.count == 2)
    }

    @Test func aRefusalShakesTheContentItWraps() async {
        let refusal = ReturnRefusal()
        let view = NSHostingView(rootView: Text(verbatim: "zzzz").modifier(RefusalShake(refusal: refusal)))
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        view.layoutSubtreeIfNeeded()
        refusal.refuse()
        for _ in 0 ..< 20 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(refusal.count == 1)
        #expect(view.fittingSize.width > 0)
    }
}
