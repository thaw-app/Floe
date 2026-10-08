//
//  TimedCacheTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct TimedCacheTests {
    @Test func aValueIsMadeOnceAndAgainWhenItHasAgedOrBeenForgotten() {
        let cache = TimedCache<String, Int>()
        var made = 0
        let start = Date(timeIntervalSince1970: 1000)
        func value(_ key: String, at seconds: TimeInterval, lasting lifetime: TimeInterval = 2) -> Int {
            cache.value(for: key, lasting: lifetime, now: start.addingTimeInterval(seconds)) {
                made += 1
                return made
            }
        }
        #expect(value("a", at: 0) == 1)
        #expect(value("a", at: 1.9) == 1, "still fresh")
        #expect(value("b", at: 1.9) == 2, "another key is its own")
        #expect(value("a", at: 2.1) == 3, "older than it lasts")
        #expect(value("a", at: 500, lasting: .infinity) == 3, "kept for good when asked to be")
        cache.forget()
        #expect(value("a", at: 500, lasting: .infinity) == 4)
        #expect(made == 4)
    }
}
