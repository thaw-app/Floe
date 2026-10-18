//
//  IconSymbolsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct IconSymbolsTests {
    @Test func everyRaycastNameInTheTableDrawsARealSymbol() {
        let missing = IconSymbols.table.filter { NSImage(systemSymbolName: $0.value, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "\(missing.keys.sorted())")
    }

    @Test func theTableHoldsOnlyNamesTheSplitGetsWrong() {
        let redundant = IconSymbols.table.filter { $0.key.replacing(#/([a-z0-9])([A-Z])/#) { "\($0.1).\($0.2)" }.lowercased() == $0.value }
        #expect(redundant.isEmpty, "\(redundant.keys.sorted())")
    }

    @Test func numbersUpToFiftyAreNumberedSquares() {
        #expect(IconSymbols.number("Number00") == "0.square")
        #expect(IconSymbols.number("Number42") == "42.square")
        #expect(IconSymbols.number("Number51") == nil, "SF Symbols has no square past 50")
        #expect(IconSymbols.number("Numbers") == nil)
    }
}
