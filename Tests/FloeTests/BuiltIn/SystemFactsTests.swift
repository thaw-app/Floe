//
//  SystemFactsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SystemFactsTests {
    private let english = Locale(identifier: "en_US")

    private func battery(
        _ percent: Double, charging: Bool = false, full: Bool = false, plugged: Bool = false, toEmpty: Int? = nil, toFull: Int? = nil
    ) -> BatteryReading {
        BatteryReading(
            chargePercent: percent, isCharging: charging, isFullyCharged: full, isExternalConnected: plugged,
            healthPercent: nil, cycleCount: nil, timeToEmptyMinutes: toEmpty, timeToFullMinutes: toFull
        )
    }

    private func readers(battery: BatteryReading? = nil, address: AddressReading? = nil, devices: [DeviceBatteryReading] = []) -> SystemFacts.Readers {
        SystemFacts.Readers(
            battery: { battery },
            devices: { devices },
            disk: { SystemFacts.Disk(name: "Macintosh HD", free: 212_000_000_000, total: 494_000_000_000) },
            memory: { MemoryReading(total: 16 * 1024 * 1024 * 1024, used: 11 * 1024 * 1024 * 1024) },
            address: { address }
        )
    }

    @Test func theBatterySaysItsChargeAndWhatItIsDoing() {
        let row: (BatteryReading) -> AnswerRow = { SystemFacts.row(for: $0, locale: english) }
        #expect(row(battery(82, toEmpty: 190)).text == "82%")
        #expect(row(battery(82, toEmpty: 190)).subtitle == "3 hr, 10 min left")
        #expect(row(battery(82)).subtitle == "On battery")
        #expect(row(battery(40, charging: true, plugged: true, toFull: 80)).subtitle == "Charging, 1 hr, 20 min until full")
        #expect(row(battery(40, charging: true, plugged: true)).subtitle == "Charging")
        #expect(row(battery(100, full: true, plugged: true)).subtitle == "Fully charged")
        #expect(row(battery(80, plugged: true)).subtitle == "On the power adapter")
        var worn = battery(82)
        worn.cycleCount = 312
        worn.healthPercent = 91.4
        #expect(row(worn).subtitle == "On battery · 312 cycles · 91% health")
    }

    @Test func eachWordAloneGivesItsFactAndAMacWithoutOneGivesNothing() {
        let facts = readers(address: AddressReading(address: "192.168.1.20", interface: "en0"))
        #expect(SystemFacts.row(for: "Disk", readers: facts, locale: english)?.text == "212 GB free")
        #expect(SystemFacts.row(for: "disk", readers: facts, locale: english)?.subtitle == "Of 494 GB on Macintosh HD")
        #expect(SystemFacts.row(for: "memory", readers: facts, locale: english)?.text == "11 GB used")
        #expect(SystemFacts.row(for: "memory", readers: facts, locale: english)?.subtitle == "Of 16 GB")
        #expect(SystemFacts.row(for: "ip", readers: facts, locale: english)?.text == "192.168.1.20")
        #expect(SystemFacts.row(for: "ip", readers: facts, locale: english)?.subtitle == "en0")
        #expect(SystemFacts.row(for: "battery", readers: facts, locale: english) == nil, "a Mac with no battery")
        #expect(SystemFacts.row(for: "ip", readers: readers(), locale: english) == nil, "a Mac on no network")
        #expect(SystemFacts.row(for: "disk space", readers: facts, locale: english) == nil)
        #expect(SystemFacts.row(for: "ip", readers: facts, locale: english)?.id == "answer:ip")
    }

    @MainActor @Test func aFactGoesUnderTheRankedRowsSoTheAppOfThatNameStaysOnTop() {
        let provider = AnswerRowSearchProvider(clipboard: { nil }, facts: readers())
        let contribution = provider.contribution(for: SearchContext(query: "disk"))
        #expect(contribution.pinned.isEmpty)
        #expect(contribution.appended.map(\.item.title) == ["212 GB free"])
        #expect(provider.contribution(for: SearchContext(query: "uuid")).pinned.count == 1, "the other answers still lead")
    }

    @Test func thisMacsOwnReadingsHoldTogether() throws {
        let memory = try #require(SystemReadings.memory())
        #expect(memory.used > 0)
        #expect(memory.used <= memory.total)
        let disk = try #require(SystemFacts.readDisk())
        #expect(disk.free <= disk.total)
        if let battery = SystemReadings.battery() {
            #expect((0 ... 100).contains(battery.chargePercent))
        }
        if let address = SystemReadings.address() {
            #expect(address.address.split(separator: ".").count == 4)
        }
    }

    @Test func batteryAlsoListsTheConnectedDevicesThatReportOne() {
        let mouse = DeviceBatteryReading(id: "m", name: "Magic Mouse", levels: [(.device, 64)])
        let buds = DeviceBatteryReading(id: "a", name: "AirPods Pro", levels: [(.left, 80), (.right, 82), (.chargingCase, 60)])
        let rows = SystemFacts.rows(for: "battery", readers: readers(battery: battery(82), devices: [buds, mouse]), locale: english)
        #expect(rows.map(\.text) == ["82%", "Left 80%, Right 82%, Case 60%", "64%"])
        #expect(rows.map(\.subtitle) == ["On battery", "AirPods Pro", "Magic Mouse"])
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(SystemFacts.rows(for: "battery", readers: readers(devices: [mouse]), locale: english).map(\.subtitle) == ["Magic Mouse"], "a Mac with no battery of its own")
        #expect(SystemFacts.rows(for: "disk", readers: readers(devices: [mouse]), locale: english).count == 1)
        #expect(SystemFacts.rows(for: "disk space", readers: readers(devices: [mouse]), locale: english).isEmpty)
    }

    @Test func aDeviceIsReadFromWhatTheRegistrySaysOfIt() {
        let mouse = SystemReadings.deviceBattery(properties: ["Product": "Magic Mouse", "BatteryPercent": 64, "SerialNumber": "S1"], registryIdentifier: 7)
        #expect(mouse == DeviceBatteryReading(id: "S1", name: "Magic Mouse", levels: [(.device, 64)]))
        let buds = SystemReadings.deviceBattery(properties: ["Name": "Buds", "BatteryPercentLeft": 80, "BatteryPercentCase": 60], registryIdentifier: 9)
        #expect(buds == DeviceBatteryReading(id: "9", name: "Buds", levels: [(.left, 80), (.chargingCase, 60)]))
        #expect(SystemReadings.deviceBattery(properties: ["Product": "Hub"], registryIdentifier: 1) == nil, "no battery, no row")
        #expect(SystemReadings.deviceBattery(properties: ["BatteryPercent": 255], registryIdentifier: 1) == nil, "a level out of range is none")
        _ = SystemReadings.deviceBatteries()
    }

    @Test func theSentinelsTheSystemPublishesAreNoEstimate() {
        #expect(SystemReadings.minutes(-1) == nil)
        #expect(SystemReadings.minutes(0) == nil)
        #expect(SystemReadings.minutes(65535) == nil)
        #expect(SystemReadings.minutes(190) == 190)
        #expect(SystemReadings.healthPercent(fullChargeCapacity: 4500, designCapacity: 5000) == 90)
        #expect(SystemReadings.healthPercent(fullChargeCapacity: 4500, designCapacity: 0) == nil)
        #expect(SystemReadings.healthPercent(fullChargeCapacity: nil, designCapacity: 5000) == nil)
    }
}
