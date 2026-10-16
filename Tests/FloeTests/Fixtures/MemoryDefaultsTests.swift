//
//  MemoryDefaultsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Testing

struct MemoryDefaultsTests {
    @Test func typedValuesGoInAndComeBackOut() {
        let defaults = MemoryDefaults()
        defaults.set(Data([1, 2]), forKey: "data")
        defaults.set(true, forKey: "bool")
        defaults.set("text", forKey: "string")
        defaults.set(["a", "b"], forKey: "strings")
        defaults.set(3, forKey: "int")
        #expect(defaults.data(forKey: "data") == Data([1, 2]))
        #expect(defaults.bool(forKey: "bool"))
        #expect(defaults.string(forKey: "string") == "text")
        #expect(defaults.stringArray(forKey: "strings") == ["a", "b"])
        #expect(defaults.integer(forKey: "int") == 3)
        defaults.removeObject(forKey: "bool")
        #expect(!defaults.bool(forKey: "bool"))
        #expect(UserDefaults.standard.object(forKey: "string") as? String != "text", "nothing reaches the app's own defaults")
    }

    @Test func eachIsEmptyAndApart() {
        let one = MemoryDefaults()
        one.set(1, forKey: "key")
        #expect(MemoryDefaults().object(forKey: "key") == nil)
        one.removePersistentDomain(forName: "any")
        #expect(one.object(forKey: "key") == nil)
    }
}
