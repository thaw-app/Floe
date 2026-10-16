//
//  DiagnosticsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct DiagnosticsTests {
    @Test func anAPIIsNamedByItsHostAndNeverItsKey() throws {
        let endpoint = try #require(AIEndpoint(baseURL: "https://api.example.com/v1", model: "m", apiKey: "sk-secret"))
        let name = AIAnswer.Choice.api(endpoint).logName
        #expect(name.contains("api.example.com"))
        #expect(!name.contains("sk-secret"))
        #expect(AIAnswer.Choice.api(nil).logName.contains("not set"))
    }

    @Test func detailedLoggingIsOffUntilTurnedOnAndIsStored() {
        let scratch = MemoryDefaults()
        let settings = AppSettings(defaults: scratch)
        #expect(!settings.diagnosticLogging)
        settings.diagnosticLogging = true
        settings.save()
        #expect(AppSettings(defaults: scratch).diagnosticLogging)
    }

    @Test func theSettingsSearchFindsTheSwitch() {
        let entry = SearchIndex.generalEntries.first { $0.id.hasSuffix("diagnosticLogging") }
        #expect(entry?.section == "Diagnostics")
    }
}
