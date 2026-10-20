//
//  SoundDevicesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreAudio
@testable import Floe
import Foundation
import Testing

@MainActor struct SoundDevicesTests {
    private let english = Locale(identifier: "en_US")
    private let speakers = AudioDevice(platformID: 1, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers", role: .output)
    private let airPods = AudioDevice(platformID: 2, uid: "70-AE-2A-5E-21-CD:output", name: "René’s AirPods Pro", role: .output, transportType: kAudioDeviceTransportTypeBluetooth)
    private let display = AudioDevice(platformID: 3, uid: "display", name: "Studio Display", role: .output, isDisplayOutput: true)
    private let microphone = AudioDevice(platformID: 4, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", role: .input)
    private let airPodsMicrophone = AudioDevice(platformID: 5, uid: "70-AE-2A-5E-21-CD:input", name: "René’s AirPods Pro", role: .input, transportType: kAudioDeviceTransportTypeBluetooth)

    private let profiler = Data("""
    {"SPBluetoothDataType": [{
      "device_connected": [
        {"René’s AirPods Pro": {"device_address": "70:AE:2A:5E:21:CD", "device_vendorID": "0x004C",
          "device_batteryLevelLeft": "80%", "device_batteryLevelRight": "82 %", "device_batteryLevelCase": "60%"}},
        {"Some Mouse": {"device_address": "11:22:33:44:55:66", "device_vendorID": "0x046D", "device_batteryLevelMain": "50%"}},
        {"AirPods Max": {"device_address": "AA:BB:CC:DD:EE:FF", "device_vendorID": "0x004c", "device_batteryLevelMain": "91%"}},
        {"Silent Beats": {"device_address": "01:02:03:04:05:06", "device_vendorID": "0x004C"}}
      ],
      "device_not_connected": [{"Old Speaker": {"device_address": "99:99:99:99:99:99"}}]
    }]}
    """.utf8)

    private func system(current: UInt32 = 1, works: Bool = true, switched: CallLog? = nil, bluetooth: Data? = nil) -> SoundDevices.System {
        let devices = [speakers, airPods, display, microphone, airPodsMicrophone]
        return SoundDevices.System(
            devices: { devices },
            current: { $0 == .output ? current : 4 },
            use: { device in
                switched?.note(device.name)
                return works
            },
            bluetooth: { bluetooth }
        )
    }

    // MARK: Batteries

    @Test func theLevelsAreReadForAppleHeadphonesThatReportAny() {
        let report = BluetoothBattery.parse(profiler)
        #expect(report.byAddress.keys.sorted() == ["70AE2A5E21CD", "AABBCCDDEEFF"])
        #expect(report.levels(for: airPods) == BatteryLevels(left: 80, right: 82, chargingCase: 60))
        #expect(report.levels(for: airPodsMicrophone) == report.levels(for: airPods), "the microphone is the same headphones")
        #expect(report.levels(for: speakers) == nil)
        #expect(report.byName["Some Mouse"] == nil, "not Apple's, so its level is not one this reads")
        #expect(BluetoothBattery.parse(Data("not json".utf8)) == BluetoothBatteryReport())
    }

    @Test func aBatteryIsWrittenByItsParts() {
        #expect(SoundDevices.batteryLabel(BatteryLevels(left: 80, right: 82, chargingCase: 60), locale: english) == "Left 80%, Right 82%, Case 60%")
        #expect(SoundDevices.batteryLabel(BatteryLevels(left: 80), locale: english) == "Left 80%")
        #expect(SoundDevices.batteryLabel(BatteryLevels(main: 91), locale: english) == "91%")
        #expect(SoundDevices.batteryLabel(BatteryLevels(), locale: english) == nil)
    }

    // MARK: Rows

    @Test func theWordAloneListsItsDevicesWithTheOneInUseFirst() {
        let rows = SoundDevices.rows(.output, query: "", system: system(current: 3))
        #expect(rows.map(\.device.name) == ["Studio Display", "MacBook Pro Speakers", "René’s AirPods Pro"])
        #expect(rows.map(\.isCurrent) == [true, false, false])
        #expect(rows.map(\.symbol) == ["display", "speaker.wave.2", "headphones"])
        #expect(rows.first?.label == "In Use")
        #expect(SoundDevices.rows(.input, query: "", system: system()).map(\.device.name) == ["MacBook Pro Microphone", "René’s AirPods Pro"])
        #expect(SoundDevices.rows(.input, query: "", system: system()).first?.symbol == "mic")
    }

    @Test func aQueryRanksByNameAndABatteryJoinsTheLabel() {
        let report = BluetoothBattery.parse(profiler)
        let rows = SoundDevices.rows(.output, query: "airp", system: system(current: 2), levels: report)
        #expect(rows.map(\.device.name) == ["René’s AirPods Pro"])
        #expect(rows.first?.label.hasPrefix("In Use · Left ") == true)
        #expect(SoundDevices.rows(.output, query: "zzz", system: system()).isEmpty)
    }

    // MARK: Choosing

    @Test func choosingADeviceSwitchesToItAndSaysSo() {
        let switched = CallLog()
        #expect(SoundDevices.use(airPods, system: system(switched: switched)) == "Sound plays through René’s AirPods Pro")
        #expect(SoundDevices.use(microphone, system: system(switched: switched)) == "The microphone is MacBook Pro Microphone")
        #expect(switched.all == ["René’s AirPods Pro", "MacBook Pro Microphone"])
        #expect(SoundDevices.use(display, system: system(works: false)) == "Couldn’t switch to Studio Display")
    }

    // MARK: The scope

    @Test func eachScopeAnswersToItsWordAndTheBatteriesArriveAfterTheRows() async throws {
        let output = SoundDeviceScope(role: .output, system: system(current: 2, bluetooth: profiler))
        #expect(output.keyword == "output")
        #expect(output.title == "Sound Output")
        #expect(output.text(in: SearchContext(query: "Output")) == "")
        #expect(output.text(in: SearchContext(query: "output air")) == "air")
        #expect(output.text(in: SearchContext(query: "outputs")) == nil)
        let first = output.results(for: "", context: SearchContext(query: "output"))
        #expect(first.map(\.title) == ["René’s AirPods Pro", "MacBook Pro Speakers", "Studio Display"])
        #expect(first.first?.rowLabel == "In Use")
        var later: [RootItem] = []
        for await batch in try #require(output.updates(for: "", context: SearchContext(query: "output"))) {
            later = batch
        }
        #expect(later.first?.rowLabel == "In Use · Left 80%, Right 82%, Case 60%")
        let row = try #require(first.last)
        #expect(row.rowLabel == "Sound Output", "a device that is not in use shows its kind")
        #expect(row.id == "sound:output:display")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(SoundRows().returnTitle(for: row) == "Use for Sound Output")

        let input = SoundDeviceScope(role: .input, system: system())
        #expect(input.keyword == "input")
        #expect(try SoundRows().returnTitle(for: #require(input.results(for: "", context: SearchContext(query: "input")).first)) == "Use as Microphone")
    }

    @Test func withoutBluetoothHeadphonesNothingMoreIsAsked() {
        let wired = SoundDevices.System(devices: { [speakers, microphone] }, current: { _ in 1 }, use: { _ in true }, bluetooth: { nil })
        #expect(SoundDeviceScope(role: .output, system: wired).updates(for: "", context: SearchContext(query: "output")) == nil)
    }

    // MARK: This Mac

    @Test func thisMacsDevicesAreReadWithoutChangingAnything() {
        let devices = AudioDevices.devices()
        #expect(Set(devices.map(\.id)).count == devices.count, "each side of each device once")
        #expect(devices.allSatisfy { !$0.name.isEmpty && !$0.uid.isEmpty })
        if let current = AudioDevices.defaultDevice(.output) {
            #expect(devices.contains { $0.platformID == current && $0.role == .output })
        }
    }
}
