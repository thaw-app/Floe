//
//  EarlierIdentifierTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct EarlierIdentifierTests {
    private let scratch: ScratchDefaults

    init() throws {
        scratch = try ScratchDefaults()
    }

    @Test func theEarlierDefaultsAreCopiedOnce() {
        let defaults = scratch.defaults
        EarlierIdentifier.importDefaults(from: ["settings": Data("{}".utf8), "hasSeenUpdateConsent": true], into: defaults)
        #expect(defaults.data(forKey: "settings") == Data("{}".utf8))
        #expect(defaults.bool(forKey: "hasSeenUpdateConsent"))

        defaults.removeObject(forKey: "hasSeenUpdateConsent")
        EarlierIdentifier.importDefaults(from: ["hasSeenUpdateConsent": true], into: defaults)
        #expect(!defaults.bool(forKey: "hasSeenUpdateConsent"))
    }

    @Test func whatThisCopyAlreadyStoredIsKept() {
        let defaults = scratch.defaults
        defaults.set(Data("mine".utf8), forKey: "settings")
        EarlierIdentifier.importDefaults(from: ["settings": Data("theirs".utf8), "usage": Data("used".utf8)], into: defaults)
        #expect(defaults.data(forKey: "settings") == Data("mine".utf8))
        #expect(defaults.data(forKey: "usage") == Data("used".utf8))
    }

    @Test func aMacThatNeverRanTheEarlierNameImportsNothing() {
        EarlierIdentifier.importDefaults(from: nil, into: scratch.defaults)
        #expect(scratch.defaults.bool(forKey: EarlierIdentifier.importedKey))
        #expect(scratch.defaults.data(forKey: "settings") == nil)
    }
}
