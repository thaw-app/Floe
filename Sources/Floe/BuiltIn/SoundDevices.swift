//
//  SoundDevices.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import CoreAudio
import Foundation

/// A sound device in the search, with whether sound goes through it now.
nonisolated struct SoundDeviceRow: Hashable, Sendable {
    var device: AudioDevice
    var isCurrent: Bool
    /// The battery levels of headphones that report them.
    var battery: String?

    /// Beside the row: that it is the one in use, and its battery.
    var label: String {
        let current = isCurrent ? String(localized: "In Use", bundle: .floe, comment: "Beside the sound device that sound goes through now.") : nil
        return [current, battery].compactMap(\.self).joined(separator: " · ")
    }

    var symbol: String {
        if device.role == .input {
            return "mic"
        }
        if device.isDisplayOutput {
            return "display"
        }
        return device.isBluetooth ? "headphones" : "speaker.wave.2"
    }
}

/// "output airpods" and "input macbook": the devices sound can go through, to choose one. The devices are read
/// and set with Audio Priority Bar's sources, see Sources/Floe/AudioPriorityBar.
nonisolated enum SoundDevices {
    /// The Mac's sound, so a test can stand in for it.
    struct System: Sendable {
        var devices: @Sendable () -> [AudioDevice] = AudioDevices.devices
        var current: @Sendable (AudioRole) -> UInt32? = AudioDevices.defaultDevice
        var use: @Sendable (AudioDevice) -> Bool = { AudioDevices.setDefault($0.platformID, role: $0.role) }
        /// The system's Bluetooth report, which holds the battery levels.
        var bluetooth: @Sendable () async -> Data? = {
            try? await Data(Shell.run(URL(fileURLWithPath: "/usr/sbin/system_profiler"), BluetoothBattery.profilerArguments).output.utf8)
        }
    }

    static func keyword(for role: AudioRole) -> String {
        role.rawValue
    }

    /// The devices of a role that match, the one in use first when nothing is typed.
    static func rows(_ role: AudioRole, query: String, system: System, levels: BluetoothBatteryReport = .init()) -> [SoundDeviceRow] {
        let current = system.current(role)
        let rows = system.devices().filter { $0.role == role }.map {
            SoundDeviceRow(device: $0, isCurrent: $0.platformID == current, battery: levels.levels(for: $0).flatMap { batteryLabel($0) })
        }
        guard !query.isEmpty else {
            let (others, current) = rows.partitioned(by: \.isCurrent)
            return current + others
        }
        return rows.ranked { Fuzzy.score(query, $0.device.name) }
    }

    /// "Left 80%, Right 82%, Case 60%", or the one level of headphones with one battery.
    static func batteryLabel(_ levels: BatteryLevels, locale: Locale = .current) -> String? {
        let percent: (Int) -> String = { (Double($0) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale)) }
        if let main = levels.main {
            return percent(main)
        }
        let parts = [
            levels.left.map { String(localized: "Left \(percent($0))", bundle: .floe, comment: "The battery of the left earbud. The placeholder is a percentage.") },
            levels.right.map { String(localized: "Right \(percent($0))", bundle: .floe, comment: "The battery of the right earbud. The placeholder is a percentage.") },
            levels.chargingCase.map { String(localized: "Case \(percent($0))", bundle: .floe, comment: "The battery of the earbuds' charging case. The placeholder is a percentage.") },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Makes a device the one in use, and answers with the line for the HUD.
    static func use(_ device: AudioDevice, system: System = System()) -> String {
        guard system.use(device) else {
            return String(localized: "Couldn’t switch to \(device.name)", bundle: .floe, comment: "The placeholder is the name of a sound device.")
        }
        switch device.role {
        case .output: return String(localized: "Sound plays through \(device.name)", bundle: .floe, comment: "The placeholder is the name of a sound device.")
        case .input: return String(localized: "The microphone is \(device.name)", bundle: .floe, comment: "The placeholder is the name of a sound device.")
        }
    }
}

/// The devices come at once. The batteries of Bluetooth headphones take a moment, and join the rows when they arrive.
struct SoundDeviceScope: SearchScope {
    let role: AudioRole
    var system = SoundDevices.System()

    var keyword: String {
        SoundDevices.keyword(for: role)
    }

    var title: String {
        switch role {
        case .output: String(localized: "Sound Output", bundle: .floe, comment: "The heading over the devices sound can play through.")
        case .input: String(localized: "Sound Input", bundle: .floe, comment: "The heading over the microphones.")
        }
    }

    let emptyTitle = String(localized: "No sound device matches", bundle: .floe)

    /// The word alone lists every device.
    func text(in context: SearchContext) -> String? {
        context.text(afterOrAlone: keyword)
    }

    func results(for text: String, context _: SearchContext) -> [RootItem] {
        SoundDevices.rows(role, query: text, system: system).map(RootItem.soundDevice)
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        guard system.devices().contains(where: { $0.role == role && $0.isBluetooth }) else { return nil }
        return .once { [role, system] in
            await system.bluetooth().map { SoundDevices.rows(role, query: text, system: system, levels: BluetoothBattery.parse($0)).map(RootItem.soundDevice) }
        }
    }
}
