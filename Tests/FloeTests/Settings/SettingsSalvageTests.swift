//
//  SettingsSalvageTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SettingsSalvageTests {
    private struct Sample: Decodable, Equatable {
        enum Mode: String, Decodable { case on, off }
        var name: String?
        var count: Int?
        var mode: Mode?
        var modes: [String: Mode]?
        var required: Bool
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test func aStoreThatReadsCleanlyDropsNothing() throws {
        let result = try #require(SettingsSalvage.decode(Sample.self, from: data(#"{"name":"a","count":2,"mode":"on","required":true}"#)))
        #expect(result.value == Sample(name: "a", count: 2, mode: .on, modes: nil, required: true))
        #expect(result.dropped.isEmpty)
    }

    @Test func oneValueFromANewerBuildCostsOnlyItsKey() throws {
        let result = try #require(SettingsSalvage.decode(Sample.self, from: data(#"{"name":"a","count":2,"mode":"sideways","required":true}"#)))
        #expect(result.value == Sample(name: "a", count: 2, mode: nil, modes: nil, required: true))
        #expect(result.dropped == ["mode"])
    }

    @Test func severalBadValuesAreEachDropped() throws {
        let json = #"{"name":7,"count":"many","mode":"on","modes":{"x":"on","y":"diagonal"},"required":false}"#
        let result = try #require(SettingsSalvage.decode(Sample.self, from: data(json)))
        #expect(result.value == Sample(name: nil, count: nil, mode: .on, modes: nil, required: false))
        #expect(Set(result.dropped) == ["name", "count", "modes"])
    }

    @Test func whatIsNotAnObjectOrLacksARequiredKeyIsNotRead() {
        #expect(SettingsSalvage.decode(Sample.self, from: data("[1,2]")) == nil)
        #expect(SettingsSalvage.decode(Sample.self, from: data("not json")) == nil)
        #expect(SettingsSalvage.decode(Sample.self, from: data(#"{"name":"a"}"#)) == nil)
        #expect(SettingsSalvage.decode(Sample.self, from: data(#"{"name":"a","required":"yes"}"#)) == nil)
    }
}

struct SettingsToleranceTests {
    private func scratch() -> UserDefaults {
        MemoryDefaults()
    }

    private func stored(in defaults: UserDefaults) throws -> [String: Any] {
        let data = try #require(defaults.data(forKey: "settings"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func anUnknownValueForOneSettingLeavesTheOthersAsSaved() throws {
        let defaults = scratch()
        let first = AppSettings(defaults: defaults, savesAfterEdits: false)
        first.popToRootDelay = 300
        first.aliases = ["app:safari": "s"]
        first.favorites = ["app:safari"]
        first.save()

        var object = try stored(in: defaults)
        object["launcherLayout"] = "a-layout-from-the-future"
        object["notesApp"] = 42
        try defaults.set(JSONSerialization.data(withJSONObject: object), forKey: "settings")

        let second = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(second.popToRootDelay == 300)
        #expect(second.aliases == ["app:safari": "s"])
        #expect(second.favorites == ["app:safari"])
        #expect(second.launcherLayout == AppSettings(defaults: scratch(), savesAfterEdits: false).launcherLayout)
    }

    @Test func aStoreWithoutTheOldRequiredKeysStillLoads() {
        let defaults = scratch()
        defaults.set(Data(#"{"popToRootDelay":120,"favorites":["app:notes"]}"#.utf8), forKey: "settings")
        let settings = AppSettings(defaults: defaults, savesAfterEdits: false)
        #expect(settings.popToRootDelay == 120)
        #expect(settings.favorites == ["app:notes"])
        #expect(settings.aliases.isEmpty)
        #expect(settings.includeRaycastExtensions)
    }

    @Test func importingAnExportWithOneUnknownValueKeepsTheRest() throws {
        let source = AppSettings(defaults: scratch(), savesAfterEdits: false)
        source.popToRootDelay = 45
        source.save()
        var object = try #require(JSONSerialization.jsonObject(with: source.exportedJSON()) as? [String: Any])
        object["aiSource"] = "a-source-from-the-future"
        let target = AppSettings(defaults: scratch(), savesAfterEdits: false)
        try target.importJSON(JSONSerialization.data(withJSONObject: object))
        #expect(target.popToRootDelay == 45)
        #expect(throws: (any Error).self) { try target.importJSON(Data("not json".utf8)) }
    }
}
