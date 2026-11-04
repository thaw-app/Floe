//
//  WindowServerSpaces.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.

import ColorSync
import CoreGraphics
import Foundation

// The Spaces calls from Thaw's Shims.swift and Bridging.swift. CoreGraphics exports them without a public
// header, so each @_silgen_name names the symbol and the declaration gives it its C type.

typealias CGSConnectionID = Int32
typealias CGSSpaceID = Int

/// The window server's tag for a kind of Space. Read from the raw number, so an unknown tag is no case.
enum CGSSpaceType: UInt32 {
    case user = 0
    case system = 2
    case fullscreen = 4
}

/// The window server connection shared by this process.
@_silgen_name("CGSMainConnectionID")
nonisolated func cgsMainConnectionID() -> CGSConnectionID

/// The space the user is currently looking at.
@_silgen_name("CGSGetActiveSpace")
nonisolated func cgsGetActiveSpace(_ connection: CGSConnectionID) -> CGSSpaceID

/// The space currently shown on the display named by displayUUID.
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
nonisolated func cgsManagedDisplayGetCurrentSpace(_ connection: CGSConnectionID, _ displayUUID: CFString) -> CGSSpaceID

/// The raw space-type tag for spaceID; map it through CGSSpaceType.
@_silgen_name("CGSSpaceGetType")
nonisolated func cgsSpaceGetType(_ connection: CGSConnectionID, _ spaceID: CGSSpaceID) -> UInt32

nonisolated enum WindowServerSpaces {
    /// The space the user is looking at, or nil when the window server names none.
    static func activeSpace() -> CGSSpaceID? {
        let space = cgsGetActiveSpace(cgsMainConnectionID())
        return space == 0 ? nil : space
    }

    /// The space shown on a display. The window server keys it by the display's UUID, not its number, so
    /// a display that was just detached, and has no UUID, has none.
    static func currentSpace(on display: CGDirectDisplayID) -> CGSSpaceID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(), let text = CFUUIDCreateString(nil, uuid)
        else { return nil }
        let space = cgsManagedDisplayGetCurrentSpace(cgsMainConnectionID(), text)
        return space == 0 ? nil : space
    }

    /// Whether a space holds one full-screen window rather than being a desktop.
    static func isFullScreen(_ space: CGSSpaceID) -> Bool {
        CGSSpaceType(rawValue: cgsSpaceGetType(cgsMainConnectionID(), space)) == .fullscreen
    }
}
