//
//  RowOwner.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// A feature that owns some kinds of the launcher's rows. The model asks each owner in turn, so a feature
/// brings its rows' behavior with it instead of adding a case to the model's switches.
protocol RowOwner: AnyObject {
    /// What Return does on the row, as its button says it. Nil when the row is not this owner's.
    func returnTitle(for item: RootItem) -> String?
    /// Return on the row, with the modifier keys held. False when the row is not this owner's.
    func open(_ item: RootItem, flags: NSEvent.ModifierFlags) -> Bool
    /// The row's Actions menu after what Return does. Nil when the row is not this owner's.
    func actions(for item: RootItem) -> [ItemAction?]?
    /// A key pressed on the selected row. False when it is not this owner's to take.
    func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, on item: RootItem) -> Bool
}

/// An owner answers only for what its rows have: no title of their own, no menu and no keys of their own by default.
extension RowOwner {
    func returnTitle(for _: RootItem) -> String? {
        nil
    }

    func actions(for _: RootItem) -> [ItemAction?]? {
        nil
    }

    func handleKey(_: UInt16, flags _: NSEvent.ModifierFlags, on _: RootItem) -> Bool {
        false
    }
}
