//
//  ClosureMenuItemTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct ClosureMenuItemTests {
    @Test func choosingTheItemRunsItsClosure() throws {
        var runs = 0
        let item = ClosureMenuItem(title: "Copy") { runs += 1 }
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        target.perform(action)
        target.perform(action)
        #expect(runs == 2)
        #expect(item.title == "Copy")
        #expect(item.isEnabled)
    }

    @Test func anItemCanStartOff() {
        #expect(!ClosureMenuItem(title: "Paste", isEnabled: false) {}.isEnabled)
    }
}
