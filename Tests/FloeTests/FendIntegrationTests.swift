//
//  FendIntegrationTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import FendCore
@testable import Floe
import Foundation
import Testing

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

    @Test func evaluationsProduceSyntacticSpans() throws {
        let approxRes = try Fend.evaluate("1/3")
        #expect(approxRes.spans.contains { $0.string.hasPrefix("approx.") })
        #expect(approxRes.spans.contains { $0.kind == .number })

        let unitRes = try Fend.evaluate("5 ft in meters")
        #expect(unitRes.spans.contains { $0.kind == .number && $0.string == "1.524" })
        #expect(unitRes.spans.contains { $0.kind == .identifier && $0.string.contains("meters") })

        let hexRes = try Fend.evaluate("255 to hex")
        #expect(hexRes.spans.contains { $0.kind == .number && $0.string == "ff" })

        let hexUnitRes = try Fend.evaluate("100 meters to hex")
        #expect(hexUnitRes.spans.contains { $0.kind == .number && $0.string == "64" })
        #expect(hexUnitRes.spans.contains { $0.kind == .identifier && $0.string.contains("meters") })

        let binUnitRes = try Fend.evaluate("100 meters to binary")
        #expect(binUnitRes.spans.contains { $0.kind == .number && $0.string == "1100100" })
        #expect(binUnitRes.spans.contains { $0.kind == .identifier && $0.string.contains("meters") })

        let mibRes = try Fend.evaluate("1 Mib/s")
        #expect(mibRes.string.contains("Mib"))
        #expect(!mibRes.string.contains("MiB"))

        let mibByteRes = try Fend.evaluate("1 MiB/s")
        #expect(mibByteRes.string.contains("MiB"))

        let kibRes = try Fend.evaluate("1 Kib")
        #expect(kibRes.string.contains("Kib"))
        #expect(!kibRes.string.contains("KiB"))

        let kibByteRes = try Fend.evaluate("1 KiB")
        #expect(kibByteRes.string.contains("KiB"))
    }
}
