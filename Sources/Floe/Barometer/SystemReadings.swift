//
//  SystemReadings.swift
//  Project: Barometer
//
//  Copyright (Barometer) © 2026 mackid1993
//  Barometer by mackid1993, https://github.com/mackid1993/Barometer
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Adapted for Floe from Barometer's SystemSources (BatterySource, BluetoothBatterySource, MemorySource and NetworkSource),
//  and cut down: Floe reads once for a row in the search, so the snapshots keep only what that row
//  shows, and the traffic counters, the adapter, the sensors and the watchers are left out.

import Darwin
import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

/// One reading of the Mac's internal battery.
nonisolated struct BatteryReading: Equatable, Sendable {
    /// From 0 to 100.
    var chargePercent: Double
    var isCharging: Bool
    var isFullyCharged: Bool
    var isExternalConnected: Bool
    var healthPercent: Double?
    var cycleCount: Int?
    /// Nil while the system is not estimating in that direction.
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
}

/// The battery of a mouse, a keyboard or headphones connected to the Mac, by the parts that report one.
nonisolated struct DeviceBatteryReading: Equatable, Sendable, Identifiable {
    enum Component: Equatable, Sendable {
        case device, left, right, chargingCase
    }

    var id: String
    var name: String
    var levels: [(component: Component, percent: Int)]

    static func == (lhs: DeviceBatteryReading, rhs: DeviceBatteryReading) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.levels.elementsEqual(rhs.levels) { $0 == $1 }
    }
}

/// One reading of memory in use.
nonisolated struct MemoryReading: Equatable, Sendable {
    var total: UInt64
    /// App, wired and compressed memory, in bytes.
    var used: UInt64
}

/// The address this Mac has on the network it reaches the internet through.
nonisolated struct AddressReading: Equatable, Sendable {
    var address: String
    var interface: String
}

nonisolated enum SystemReadings {
    // MARK: Battery

    /// The public IOPS summary, with AppleSmartBattery's details where the registry has them. Nil without a battery.
    static func battery() -> BatteryReading? {
        guard let summary = batterySummary() else { return nil }
        let detail = properties(matching: "AppleSmartBattery") ?? [:]
        let pack = properties(matching: "AppleSmartBatteryPack") ?? [:]
        let batteryData = detail["BatteryData"] as? [String: Any] ?? [:]
        let packData = pack["BatteryData"] as? [String: Any] ?? [:]

        let current = double(summary[kIOPSCurrentCapacityKey]) ?? 0
        let most = double(summary[kIOPSMaxCapacityKey]) ?? 100
        let isCharging = bool(summary[kIOPSIsChargingKey]) ?? bool(detail["IsCharging"]) ?? false
        let isExternalConnected = summary[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue || bool(detail["ExternalConnected"]) == true
        // The summary is authoritative when it has an estimate, and the registry's running averages are the
        // fallback. Both publish a sentinel while macOS is still computing: -1 from IOPS, 65535 from the registry.
        let timeToEmpty = minutes(summary[kIOPSTimeToEmptyKey]) ?? minutes(detail["AvgTimeToEmpty"])
            ?? minutes(batteryData["AvgTimeToEmpty"]) ?? minutes(packData["AvgTimeToEmpty"])
        let timeToFull = minutes(summary[kIOPSTimeToFullChargeKey]) ?? minutes(detail["AvgTimeToFull"])
            ?? minutes(batteryData["AvgTimeToFull"]) ?? minutes(packData["AvgTimeToFull"])
        return BatteryReading(
            chargePercent: most > 0 ? min(100, max(0, current / most * 100)) : min(100, max(0, current)),
            isCharging: isCharging,
            isFullyCharged: bool(summary[kIOPSIsChargedKey]) ?? bool(detail["FullyCharged"]) ?? false,
            isExternalConnected: isExternalConnected,
            healthPercent: healthPercent(
                fullChargeCapacity: double(batteryData["FullChargeCapacity"]) ?? double(packData["AppleRawMaxCapacity"]) ?? double(packData["FccComp1"]),
                designCapacity: double(batteryData["DesignCapacity"]) ?? double(packData["DesignCapacity"])
            ),
            cycleCount: integer(detail["CycleCount"]) ?? integer(packData["CycleCount"]),
            // An estimate only means something in the direction the battery is actually moving.
            timeToEmptyMinutes: isExternalConnected ? nil : timeToEmpty,
            timeToFullMinutes: isCharging ? timeToFull : nil
        )
    }

    static func minutes(_ value: Any?) -> Int? {
        guard let raw = (value as? NSNumber)?.intValue, raw > 0, raw < 10080 else { return nil }
        return raw
    }

    static func healthPercent(fullChargeCapacity: Double?, designCapacity: Double?) -> Double? {
        guard let fullChargeCapacity, let designCapacity, designCapacity > 0 else { return nil }
        let value = fullChargeCapacity / designCapacity * 100
        return value.isFinite && (0 ... 150).contains(value) ? value : nil
    }

    private static func batterySummary() -> [String: Any]? {
        let information = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let sources = IOPSCopyPowerSourcesList(information)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTransportTypeKey] as? String == kIOPSInternalType {
                return description
            }
        }
        return nil
    }

    private static func properties(matching className: String) -> [String: Any]? {
        guard let matching = IOServiceMatching(className) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    // MARK: Connected devices

    /// The devices in the registry that report a battery, by name. One that is listed twice is taken where it says the most.
    static func deviceBatteries() -> [DeviceBatteryReading] {
        var byIdentifier: [String: DeviceBatteryReading] = [:]
        for className in ["AppleDeviceManagementHIDEventService", "IOBluetoothDevice"] {
            for (properties, identifier) in allProperties(matching: className) {
                guard let reading = deviceBattery(properties: properties, registryIdentifier: identifier) else { continue }
                if reading.levels.count > (byIdentifier[reading.id]?.levels.count ?? 0) {
                    byIdentifier[reading.id] = reading
                }
            }
        }
        return byIdentifier.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func deviceBattery(properties: [String: Any], registryIdentifier: UInt64) -> DeviceBatteryReading? {
        let string: ([String]) -> String? = { keys in keys.lazy.compactMap { properties[$0] as? String }.first }
        let percent: ([String]) -> Int? = { keys in
            keys.lazy.compactMap { (properties[$0] as? NSNumber)?.intValue }.first { (0 ... 100).contains($0) }
        }
        let parts: [(DeviceBatteryReading.Component, [String])] = [
            (.device, ["BatteryPercent", "BatteryPercentSingle", "BatteryLevel"]),
            (.left, ["BatteryPercentLeft"]),
            (.right, ["BatteryPercentRight"]),
            (.chargingCase, ["BatteryPercentCase"]),
        ]
        let levels = parts.compactMap { part, keys in percent(keys).map { (component: part, percent: $0) } }
        guard !levels.isEmpty else { return nil }
        return DeviceBatteryReading(
            id: string(["DeviceAddress", "SerialNumber"]) ?? String(registryIdentifier),
            name: string(["Product", "ProductName", "DeviceName", "Name"]) ?? "Bluetooth Device",
            levels: levels
        )
    }

    private static func allProperties(matching className: String) -> [([String: Any], UInt64)] {
        guard let matching = IOServiceMatching(className) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [([String: Any], UInt64)] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var unmanagedProperties: Unmanaged<CFMutableDictionary>?
            var identifier: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS,
                  IORegistryEntryCreateCFProperties(service, &unmanagedProperties, nil, 0) == KERN_SUCCESS,
                  let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
            else { continue }
            result.append((properties, identifier))
        }
        return result
    }

    // MARK: Memory

    static func memory() -> MemoryReading? {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0, let pageSize, let statistics = virtualMemoryStatistics() else { return nil }
        let internalPages = UInt64(statistics.internal_page_count)
        let purgeablePages = UInt64(statistics.purgeable_count)
        let appPages = internalPages >= purgeablePages ? internalPages - purgeablePages : 0
        let pages = appPages + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
        return MemoryReading(total: total, used: min(total, pages * pageSize))
    }

    /// The page size never changes while the system is running, so it is read once.
    private static let pageSize: UInt64? = {
        var value: vm_size_t = 0
        // The send right mach_host_self returns must be released.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        return host_page_size(host, &value) == KERN_SUCCESS ? UInt64(value) : nil
    }()

    private static func virtualMemoryStatistics() -> vm_statistics64? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        return result == KERN_SUCCESS ? statistics : nil
    }

    // MARK: Network

    /// The IPv4 address of the primary interface, as the system's network configuration names it. Nothing is sent.
    static func address() -> AddressReading? {
        let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        guard let primary = global?["PrimaryInterface"] as? String else { return nil }
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }
        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, Int32(address.pointee.sa_family) == AF_INET, String(cString: interface.ifa_name) == primary,
                  let numeric = numericAddress(address)
            else { continue }
            return AddressReading(address: numeric, interface: primary)
        }
        return nil
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        return String(bytes: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}
