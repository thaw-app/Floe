//
//  BluetoothBattery.swift
//  Project: Audio Priority Bar
//
//  Copyright (Audio Priority Bar) © 2024 tobi, © 2026 Camille Guillory
//  Audio Priority Bar by Camille Guillory, https://github.com/camguillory/Audio-Priority-Bar
//  Licensed under the MIT License
//
//  Floe changes © 2026 René Jiménez, under the GNU AGPLv3.
//
//  Adapted for Floe from Audio Priority Bar's AudioPriorityCore/BluetoothBattery.swift, and cut down:
//  Floe reads the levels once for a list in the search, so the paired devices that are not connected,
//  the Jabra headsets and the monitor that keeps a report up to date are left out.

import Foundation

/// Battery percentages one Bluetooth device reports, each nil while it reports nothing for that part,
/// as for a pod sitting in a closed case.
nonisolated struct BatteryLevels: Equatable, Sendable {
    var left: Int?
    var right: Int?
    var chargingCase: Int?
    /// Headphones with one battery, such as AirPods Max.
    var main: Int?

    var isEmpty: Bool {
        left == nil && right == nil && chargingCase == nil && main == nil
    }
}

nonisolated struct BluetoothBatteryReport: Equatable, Sendable {
    /// Keyed by address, uppercased hex digits with separators removed.
    var byAddress: [String: BatteryLevels] = [:]
    var byName: [String: BatteryLevels] = [:]

    /// Levels for an audio device. CoreAudio gives a Bluetooth device a UID built from its address, such as
    /// 70-AE-2A-5E-21-CD:output; the name is a fallback for a UID in some other shape.
    func levels(for device: AudioDevice) -> BatteryLevels? {
        let uid = BluetoothBattery.normalizedAddress(device.uid)
        if let match = byAddress.first(where: { uid.hasPrefix($0.key) }) {
            return match.value
        }
        return byName[device.name]
    }
}

nonisolated enum BluetoothBattery {
    /// Apple's Bluetooth vendor ID, carried by AirPods and Beats.
    static let appleVendorID = "0x004C"
    /// The arguments that make system_profiler write the report that parse(_:) reads. It needs no Bluetooth permission.
    static let profilerArguments = ["-json", "SPBluetoothDataType"]

    static func normalizedAddress(_ text: String) -> String {
        String(text.uppercased().filter(\.isHexDigit))
    }

    /// Parses system_profiler -json SPBluetoothDataType, keeping connected Apple headphones that report at least one level.
    static func parse(_ data: Data) -> BluetoothBatteryReport {
        var report = BluetoothBatteryReport()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return report }
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any],
                          (info["device_vendorID"] as? String)?.uppercased() == appleVendorID.uppercased()
                    else { continue }
                    let levels = BatteryLevels(
                        left: percent(info["device_batteryLevelLeft"]),
                        right: percent(info["device_batteryLevelRight"]),
                        chargingCase: percent(info["device_batteryLevelCase"]),
                        main: percent(info["device_batteryLevelMain"])
                    )
                    guard !levels.isEmpty else { continue }
                    if let address = info["device_address"] as? String {
                        report.byAddress[normalizedAddress(address)] = levels
                    }
                    report.byName[name] = levels
                }
            }
        }
        return report
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
}
