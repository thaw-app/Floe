//
//  SystemFacts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// "battery", "disk", "memory" and "ip": what this Mac says about itself right now. Return copies it.
/// The battery, the memory and the address are read by Barometer's sources, see SystemReadings.swift.
nonisolated enum SystemFacts: String, CaseIterable, Sendable {
    case battery, disk, memory, ip

    struct Disk: Equatable {
        var name: String
        var free: Int64
        var total: Int64
    }

    /// The readers, so a test can stand in a Mac with a battery, or one without.
    struct Readers: Sendable {
        var battery: @Sendable () -> BatteryReading? = SystemReadings.battery
        var devices: @Sendable () -> [DeviceBatteryReading] = SystemReadings.deviceBatteries
        var disk: @Sendable () -> Disk? = SystemFacts.readDisk
        var memory: @Sendable () -> MemoryReading? = SystemReadings.memory
        var address: @Sendable () -> AddressReading? = SystemReadings.address
    }

    /// The row for a query that is one of the words and nothing else. Nil for a fact this Mac has none of.
    static func row(for query: String, readers: Readers = Readers(), locale: Locale = .current) -> AnswerRow? {
        switch SystemFacts(rawValue: query.lowercased()) {
        case .battery: readers.battery().map { row(for: $0, locale: locale) }
        case .disk: readers.disk().map { row(for: $0, locale: locale) }
        case .memory: readers.memory().map { row(for: $0, locale: locale) }
        case .ip: readers.address().map(row)
        case nil: nil
        }
    }

    /// Every row for a query that is one of the words: "battery" is the Mac's own, then each connected device's.
    static func rows(for query: String, readers: Readers = Readers(), locale: Locale = .current) -> [AnswerRow] {
        let own = row(for: query, readers: readers, locale: locale).map { [$0] } ?? []
        guard SystemFacts(rawValue: query.lowercased()) == .battery else { return own }
        return own + readers.devices().map { row(for: $0, locale: locale) }
    }

    // MARK: Rows

    static func row(for battery: BatteryReading, locale: Locale) -> AnswerRow {
        let length: (Int) -> String = { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale)) }
        let percent: (Double) -> String = { ($0 / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale)) }
        let state = if battery.isCharging, let minutes = battery.timeToFullMinutes {
            String(localized: "Charging, \(length(minutes)) until full", bundle: .floe, comment: "About the battery. The placeholder is a length of time, such as 1 hr 20 min.")
        } else if battery.isCharging {
            String(localized: "Charging", bundle: .floe, comment: "About the battery.")
        } else if battery.isFullyCharged {
            String(localized: "Fully charged", bundle: .floe, comment: "About the battery.")
        } else if battery.isExternalConnected {
            String(localized: "On the power adapter", bundle: .floe, comment: "About the battery: plugged in and not charging.")
        } else if let minutes = battery.timeToEmptyMinutes {
            String(localized: "\(length(minutes)) left", bundle: .floe, comment: "About the battery. The placeholder is a length of time, such as 3 hr 10 min.")
        } else {
            String(localized: "On battery", bundle: .floe, comment: "About the battery: not plugged in.")
        }
        let cycles = battery.cycleCount.map { String(localized: "\($0) cycles", bundle: .floe, comment: "About the battery: how many times it has been charged and emptied.") }
        let health = battery.healthPercent.map { String(localized: "\(percent($0)) health", bundle: .floe, comment: "About the battery: how much of its first capacity it still holds. The placeholder is a percentage, such as 91%.") }
        return AnswerRow(
            id: "battery",
            text: percent(battery.chargePercent),
            subtitle: [state, cycles, health].compactMap(\.self).joined(separator: " · "),
            kind: String(localized: "Battery", bundle: .floe, comment: "The kind of a result, shown beside its title."),
            symbol: "battery.75percent"
        )
    }

    static func row(for device: DeviceBatteryReading, locale: Locale) -> AnswerRow {
        let percent: (Int) -> String = { (Double($0) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale)) }
        let levels = device.levels.map { level in
            switch level.component {
            case .device: percent(level.percent)
            case .left: String(localized: "Left \(percent(level.percent))", bundle: .floe, comment: "The battery of the left earbud. The placeholder is a percentage.")
            case .right: String(localized: "Right \(percent(level.percent))", bundle: .floe, comment: "The battery of the right earbud. The placeholder is a percentage.")
            case .chargingCase: String(localized: "Case \(percent(level.percent))", bundle: .floe, comment: "The battery of the earbuds' charging case. The placeholder is a percentage.")
            }
        }
        return AnswerRow(
            id: "battery:\(device.id)",
            text: levels.joined(separator: ", "),
            subtitle: device.name,
            kind: String(localized: "Battery", bundle: .floe, comment: "The kind of a result, shown beside its title."),
            symbol: "battery.50percent"
        )
    }

    static func row(for disk: Disk, locale: Locale) -> AnswerRow {
        let free = disk.free.formatted(.byteCount(style: .file).locale(locale))
        let total = disk.total.formatted(.byteCount(style: .file).locale(locale))
        return AnswerRow(
            id: "disk",
            text: String(localized: "\(free) free", bundle: .floe, comment: "How much room a disk has left. The placeholder is a size, such as 212 GB."),
            subtitle: String(localized: "Of \(total) on \(disk.name)", bundle: .floe, comment: "Under how much room a disk has left. The first placeholder is its size, such as 494 GB, the second its name."),
            kind: String(localized: "Disk", bundle: .floe, comment: "The kind of a result, shown beside its title."),
            symbol: "internaldrive"
        )
    }

    static func row(for memory: MemoryReading, locale: Locale) -> AnswerRow {
        let used = Int64(memory.used).formatted(.byteCount(style: .memory).locale(locale))
        let total = Int64(memory.total).formatted(.byteCount(style: .memory).locale(locale))
        return AnswerRow(
            id: "memory",
            text: String(localized: "\(used) used", bundle: .floe, comment: "How much memory is in use. The placeholder is a size, such as 11 GB."),
            subtitle: String(localized: "Of \(total)", bundle: .floe, comment: "Under how much memory is in use. The placeholder is how much the Mac has, such as 16 GB."),
            kind: String(localized: "Memory", bundle: .floe, comment: "The kind of a result, shown beside its title."),
            symbol: "memorychip"
        )
    }

    static func row(for address: AddressReading) -> AnswerRow {
        AnswerRow(
            id: "ip",
            text: address.address,
            subtitle: address.interface,
            kind: String(localized: "Local Address", bundle: .floe, comment: "The kind of a result, shown beside its title. Here this Mac's address on the local network."),
            symbol: "network"
        )
    }

    // MARK: Reading

    /// The startup disk, with the room the system would make by clearing what it can.
    static func readDisk() -> Disk? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeNameKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity
        else { return nil }
        return Disk(name: values.volumeName ?? "/", free: free, total: Int64(total))
    }
}
