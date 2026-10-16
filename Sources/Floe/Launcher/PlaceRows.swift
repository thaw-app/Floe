//
//  PlaceRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Places Apple Maps found: Return shows one in Maps.
final class PlaceRows {
    var host = RowHost()

    func placeActions(for place: Place) -> [ItemAction?] {
        [
            nil,
            ItemAction(title: String(localized: "Get Directions", bundle: .floe, comment: "A button that opens the way to a place in Maps."), symbol: "arrow.triangle.turn.up.right.diamond") { [weak self] in
                self?.host.reach(Places.link(to: place, directions: true))
            },
            ItemAction(title: String(localized: "Copy Address", bundle: .floe), symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(place.address.isEmpty ? place.name : place.address)
                self?.host.showHUD(String(localized: "Copied", bundle: .floe, comment: "Shown briefly after something was put on the clipboard."))
            },
        ]
    }
}

extension PlaceRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case .place = item else { return nil }
        return String(localized: "Open in Maps", bundle: .floe, comment: "Maps is the name of Apple's app.")
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .place(place) = item else { return false }
        host.reach(Places.link(to: place))
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .place(place) = item else { return nil }
        return placeActions(for: place)
    }
}
