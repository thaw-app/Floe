//
//  ExtensionSettingsSyncTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ExtensionSettingsSyncTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-extension-sync-\(UUID().uuidString)")
    private let cloud = MemorySyncCloud()

    /// A weather extension with one preference of every kind, and one that belongs to its command.
    private var weather: ExtensionCommand {
        Fixture.command(
            "forecast",
            extension: "weather",
            extensionPreferences: [
                Fixture.field("city"),
                Fixture.field("metric", type: "checkbox"),
                Fixture.field("units", type: "dropdown", options: [("Celsius", "c"), ("Fahrenheit", "f")]),
                Fixture.field("token", type: "password"),
                Fixture.field("export", type: "file"),
                Fixture.field("cache", type: "directory"),
                Fixture.field("browser", type: "appPicker"),
            ],
            commandPreferences: [Fixture.field("days")]
        )
    }

    private func floe(_ name: String, installs commands: [ExtensionCommand]) throws -> SyncedFloe {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mac = try SyncedFloe(cloud: cloud, folder: folder, name: name)
        mac.installed.commands = commands
        mac.service.engine.setOn(true)
        return mac
    }

    private func record(in mac: SyncedFloe, of name: String) -> String? {
        (mac.store.values["ext/\(name)"] as? [String: Any])?["v"] as? String
    }

    @Test func aPreferenceChangedOnOneMacArrivesOnTheOther() throws {
        let a = try floe("a", installs: [weather])
        let b = try floe("b", installs: [weather])
        b.installed.stored["weather"] = ["city": "Lisbon", "forecast/days": "3"]
        b.changed(at: 1500)
        a.installed.stored["weather"] = ["city": "Oslo", "metric": true, "units": "f", "forecast/days": "7"]
        a.changed(at: 2000)
        cloud.deliver()
        let arrived = try #require(b.installed.stored["weather"])
        #expect(arrived["city"] as? String == "Oslo")
        #expect(arrived["metric"] as? Bool == true)
        #expect(arrived["units"] as? String == "f")
        #expect(arrived["forecast/days"] as? String == "7", "a command's own preference travels under its command")
        #expect(a.store.values.keys.count { $0.hasPrefix("ext/") } == 1, "one record for the extension, not one for each preference")
        #expect(b.service.engine.status.skipped == 0)
    }

    @Test func aPasswordAndAPathNeverLeaveAndAreLeftAloneHere() throws {
        let a = try floe("a", installs: [weather])
        let b = try floe("b", installs: [weather])
        b.installed.stored["weather"] = ["token": "b-secret", "export": "/Users/b/out.csv", "cache": "/Users/b/Cache", "browser": "/Applications/Safari.app"]
        b.changed(at: 1500)
        a.installed.stored["weather"] = ["city": "Oslo", "token": "a-secret", "export": "/Users/a/out.csv", "cache": "/Users/a/Cache", "browser": "/Applications/Arc.app"]
        a.changed(at: 2000)
        cloud.deliver()
        #expect(record(in: a, of: "weather") == "{\"city\":\"Oslo\"}")
        let everything = "\(a.store.values) \(b.store.values) \(a.extensions.held) \(b.extensions.held)"
        for kept in ["secret", "/Users/", "/Applications/"] {
            #expect(!everything.contains(kept))
        }
        let here = try #require(b.installed.stored["weather"])
        #expect(here["city"] as? String == "Oslo")
        #expect(here["token"] as? String == "b-secret")
        #expect(here["export"] as? String == "/Users/b/out.csv")
        #expect(here["cache"] as? String == "/Users/b/Cache")
        #expect(here["browser"] as? String == "/Applications/Safari.app")
    }

    @Test func aRecordThatNamesAPasswordOrAPathDoesNotWriteIt() throws {
        let b = try floe("b", installs: [weather])
        b.store.plant(["t": 5000.0, "d": "x", "v": "{\"city\":\"Oslo\",\"token\":\"theirs\",\"cache\":\"/Users/x\",\"unknown\":\"y\",\"metric\":\"yes\",\"units\":\"kelvin\"}"], for: "ext/weather")
        b.service.engine.refresh()
        let here = try #require(b.installed.stored["weather"])
        #expect(here.keys.sorted() == ["city"], "a value of the wrong type, or a dropdown value this version lacks, is left out too")
    }

    @Test func anExtensionMissingHereKeepsItsRecordAndTakesItOnceInstalled() throws {
        let a = try floe("a", installs: [weather])
        let b = try floe("b", installs: [])
        a.installed.stored["weather"] = ["city": "Oslo"]
        a.changed(at: 2000)
        cloud.deliver()
        let sent = try #require(a.store.values["ext/weather"] as? [String: Any])
        #expect(b.installed.stored.isEmpty)
        b.changed(at: 2500)
        cloud.deliver()
        let kept = try #require(b.store.values["ext/weather"] as? [String: Any])
        #expect(NSDictionary(dictionary: kept) == NSDictionary(dictionary: sent), "the Mac without the extension does not rewrite the record")
        #expect(b.service.engine.status.skipped == 0)
        b.installed.commands = [weather]
        b.changed(at: 3000)
        #expect(b.installed.stored["weather"]?["city"] as? String == "Oslo")
        cloud.deliver()
        #expect(a.installed.stored["weather"]?["city"] as? String == "Oslo")
    }

    @Test func removingAnExtensionOnOneMacLeavesItsRecordAndTheOtherMac() throws {
        let a = try floe("a", installs: [weather])
        let b = try floe("b", installs: [weather])
        a.installed.stored["weather"] = ["city": "Oslo"]
        a.changed(at: 2000)
        cloud.deliver()
        a.installed.commands = []
        a.installed.stored["weather"] = nil
        a.changed(at: 3000)
        cloud.deliver()
        #expect(record(in: a, of: "weather") == "{\"city\":\"Oslo\"}")
        #expect(b.installed.stored["weather"]?["city"] as? String == "Oslo")
        #expect(b.installed.commands.count == 1)
    }

    @Test func withTheSwitchOffNothingIsSentOrAppliedUntilItIsOn() throws {
        let a = try floe("a", installs: [weather])
        let b = try floe("b", installs: [weather])
        b.settings.syncsExtensionSettings = false
        b.installed.stored["weather"] = ["city": "Lisbon"]
        b.changed(at: 1500)
        cloud.deliver()
        #expect(record(in: b, of: "weather") == nil)
        #expect(a.installed.stored["weather"] == nil, "nothing of the Mac with the switch off is sent")
        a.installed.stored["weather"] = ["city": "Oslo"]
        a.changed(at: 2000)
        cloud.deliver()
        #expect(b.installed.stored["weather"]?["city"] as? String == "Lisbon", "and nothing is applied there")
        #expect(b.service.engine.status.skipped == 0)
        b.settings.syncsExtensionSettings = true
        b.changed(at: 3000)
        #expect(b.installed.stored["weather"]?["city"] as? String == "Oslo", "what arrived meanwhile is applied when the switch goes on")
    }

    @Test func aMalformedRecordIsSkippedAndCounted() throws {
        let b = try floe("b", installs: [weather])
        b.installed.stored["weather"] = ["city": "Lisbon"]
        b.changed(at: 1500)
        b.store.plant(["t": 5000.0, "d": "x", "v": "[\"Oslo\"]"], for: "ext/weather")
        b.store.plant(["t": 5000.0, "d": "x", "v": "\"Oslo\""], for: "ext/other")
        b.service.engine.refresh()
        #expect(b.installed.stored["weather"]?["city"] as? String == "Lisbon")
        #expect(b.service.engine.status.skipped == 2)
        #expect(b.extensions.held.pending.isEmpty)
    }

    @Test func twoMacsEditingOneExtensionAtOnceEndWithTheNewerRecord() throws {
        let a = try floe("a", installs: [weather])
        let b = try floe("b", installs: [weather])
        a.installed.stored["weather"] = ["city": "Oslo", "forecast/days": "3"]
        a.changed(at: 2000)
        cloud.deliver()
        b.store.isOnline = false
        a.installed.stored["weather"]?["city"] = "Bergen"
        a.changed(at: 3000)
        b.installed.stored["weather"]?["forecast/days"] = "7"
        b.changed(at: 3100)
        b.store.isOnline = true
        cloud.deliver()
        for mac in [a, b] {
            #expect(mac.installed.stored["weather"]?["city"] as? String == "Oslo", "the older record's edit is lost: the record is merged whole")
            #expect(mac.installed.stored["weather"]?["forecast/days"] as? String == "7")
        }
    }

    @Test func onlyThePlainKindsOfPreferenceSync() {
        let fields = ExtensionSettingsSync.fields(of: [weather])
        #expect(fields["weather"]?.keys.sorted() == ["city", "forecast/days", "metric", "units"])
        #expect(ExtensionSettingsSync.syncedTypes.isDisjoint(with: ["password", "file", "directory", "appPicker"]))
    }
}
