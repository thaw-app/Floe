//
//  SystemToggles.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import AudioToolbox
import CoreAudio
import CoreWLAN
import Foundation
import IOKit.pwr_mgt

/// The system commands that flip a setting. Each returns the line the HUD shows, which says
/// what the setting is now or why it did not change.
enum SystemToggle {
    // MARK: Wi-Fi

    static func flipWiFi() -> String {
        guard let interface = CWWiFiClient.shared().interface() else { return String(localized: "This Mac has no Wi-Fi", bundle: .floe) }
        let turnOn = !interface.powerOn()
        do {
            try interface.setPower(turnOn)
            return turnOn ? String(localized: "Wi-Fi On", bundle: .floe) : String(localized: "Wi-Fi Off", bundle: .floe)
        } catch {
            return turnOn
                ? String(localized: "Couldn't turn Wi-Fi on", bundle: .floe)
                : String(localized: "Couldn't turn Wi-Fi off", bundle: .floe)
        }
    }

    // MARK: Mute

    static func flipMute() -> String {
        guard let device = defaultOutputDevice() else { return String(localized: "No sound output", bundle: .floe) }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue,
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else { return String(localized: "This output can't be muted", bundle: .floe) }
        var flipped: UInt32 = muted == 0 ? 1 : 0
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &flipped) == noErr else { return String(localized: "Couldn't change the sound", bundle: .floe) }
        return flipped == 1 ? String(localized: "Muted", bundle: .floe, comment: "Said after the sound was turned off.") : String(localized: "Unmuted", bundle: .floe, comment: "Said after the sound was turned back on.")
    }

    // MARK: Volume

    /// One press of a volume key: a sixteenth of the range.
    static let volumeStep: Float = 1.0 / 16

    /// The volume after a step, kept between silence and full.
    static func volume(_ volume: Float, steppedBy step: Float) -> Float {
        min(1, max(0, volume + step))
    }

    static func stepVolume(by step: Float) -> String {
        guard let device = defaultOutputDevice() else { return String(localized: "No sound output", bundle: .floe) }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var current: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue,
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr
        else { return String(localized: "This output has no volume to change", bundle: .floe) }
        var stepped = volume(current, steppedBy: step)
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &stepped) == noErr else { return String(localized: "Couldn't change the sound", bundle: .floe) }
        return String(localized: "Volume \(Int((stepped * 100).rounded()))%", bundle: .floe, comment: "Said after the volume changed. The placeholder is a number from 0 to 100.")
    }

    // MARK: Bluetooth

    /// macOS has no public call that turns Bluetooth on or off; these two are the ones its own settings use.
    private static let bluetoothPower: (get: @convention(c) () -> Int32, set: @convention(c) (Int32) -> Int32)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW),
              let get = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState"),
              let set = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else { return nil }
        return (unsafeBitCast(get, to: (@convention(c) () -> Int32).self), unsafeBitCast(set, to: (@convention(c) (Int32) -> Int32).self))
    }()

    static func flipBluetooth() -> String {
        guard let power = bluetoothPower else { return String(localized: "Couldn't change Bluetooth", bundle: .floe) }
        let turnOn = power.get() == 0
        _ = power.set(turnOn ? 1 : 0)
        return turnOn ? String(localized: "Bluetooth On", bundle: .floe) : String(localized: "Bluetooth Off", bundle: .floe)
    }

    // MARK: Disks

    /// Whether a mounted volume is one to eject: a network volume, or a local one macOS places outside
    /// the Mac or calls removable. The rule is Thaw's, from the monitor behind its external drive trigger.
    static func isEjectable(isInternal: Bool?, isRemovable: Bool, isNetwork: Bool) -> Bool {
        isNetwork || isInternal == false || isRemovable
    }

    static func ejectableVolumes() -> [URL] {
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            return isEjectable(
                isInternal: values.volumeIsInternal,
                isRemovable: values.volumeIsRemovable == true || values.volumeIsEjectable == true,
                isNetwork: values.volumeIsLocal == false
            )
        }
    }

    static func ejectDisks() -> String {
        let volumes = ejectableVolumes()
        guard !volumes.isEmpty else { return String(localized: "No disks to eject", bundle: .floe) }
        let refused = volumes.filter { (try? NSWorkspace.shared.unmountAndEjectDevice(at: $0)) == nil }
        return ejectSummary(ejected: volumes.count - refused.count, refused: refused.map(\.lastPathComponent))
    }

    /// The line for the HUD: how many went, or the names of the ones that are in use.
    static func ejectSummary(ejected: Int, refused: [String]) -> String {
        guard refused.isEmpty else {
            return String(localized: "Couldn't eject \(refused.formatted(.list(type: .and)))", bundle: .floe, comment: "The placeholder is a list of disk names.")
        }
        return String(localized: "Ejected disks: \(ejected)", bundle: .floe, comment: "The placeholder is a number.")
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    // MARK: Keep awake

    /// The assertion that holds the display awake; 0 while there is none. Only touched on the main thread.
    private static var awakeAssertion: IOPMAssertionID = 0

    static var isKeepingAwake: Bool {
        awakeAssertion != 0
    }

    /// Lasts until it is flipped back or Floe quits: the system drops the assertion with the process.
    static func flipKeepAwake() -> String {
        if awakeAssertion != 0 {
            IOPMAssertionRelease(awakeAssertion)
            awakeAssertion = 0
            return String(localized: "Your Mac can sleep again", bundle: .floe)
        }
        var assertion: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Floe: Keep Awake" as CFString,
            &assertion
        )
        guard status == kIOReturnSuccess else { return String(localized: "Couldn't keep your Mac awake", bundle: .floe) }
        awakeAssertion = assertion
        return String(localized: "Keeping your Mac awake", bundle: .floe)
    }
}
