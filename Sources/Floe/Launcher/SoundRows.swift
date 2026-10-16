//
//  SoundRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Sound devices the search found: Return makes one the device sound plays through or records from.
final class SoundRows {
    var host = RowHost()

    static func title(for role: AudioRole) -> String {
        switch role {
        case .output: String(localized: "Use for Sound Output", bundle: .floe, comment: "A button that makes the selected device the one sound plays through.")
        case .input: String(localized: "Use as Microphone", bundle: .floe, comment: "A button that makes the selected device the one that records.")
        }
    }

    /// Return on a sound device: the panel goes, and the HUD says where sound goes now.
    func use(_ row: SoundDeviceRow) {
        host.leave()
        host.showHUD(SoundDevices.use(row.device))
    }
}

extension SoundRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case let .soundDevice(row) = item else { return nil }
        return Self.title(for: row.device.role)
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .soundDevice(row) = item else { return false }
        use(row)
        return true
    }
}
