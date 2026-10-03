//
//  FendIntegrationTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import FendCore
import Foundation
import Testing
@testable import Floe

struct FendIntegrationTests {
    @Test func fendVersionIsAvailable() {
        #expect(!Fend.version.isEmpty)
    }

    @Test func mathEvaluationsProduceExpectedResults() throws {
        #expect(try Fend.evaluate("2 + 3 * 4") == "14")
        #expect(try Fend.evaluate("2^10") == "1024")
        #expect(try Fend.evaluate("sqrt(256)") == "16")
    }

    @Test func unitConversionsProduceExpectedResults() throws {
        let km = try Fend.evaluate("10 miles to km")
        #expect(km.contains("16.09") || km.contains("km"))

        let bytes = try Fend.evaluate("1 GiB in MiB")
        #expect(bytes == "1024 MiB")
    }

    @Test func isolatedContextSupportsStatefulVariables() throws {
        let context = try FendContext()
        _ = try context.evaluate("radius = 5")
        let area = try context.evaluate("pi * radius^2")
        #expect(area.value.contains("78.53"))
    }
}
