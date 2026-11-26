//
//  MenuBarApp.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The app that hides menu bar items whose actions the search lists: Thaw or Punkto. Punkto does
/// nothing while Thaw runs, so the search offers one of them, never both.
nonisolated enum MenuBarApp: String, Codable, CaseIterable, Identifiable, Sendable {
    case thaw
    case punkto

    var id: String {
        rawValue
    }

    /// The app's name, which is the same in every language.
    var name: String {
        switch self {
        case .thaw: "Thaw"
        case .punkto: "Punkto"
        }
    }

    /// The one in use: the user's choice, or without one Thaw when it is installed, then Punkto.
    static func resolved(chosen: MenuBarApp?, thawIsInstalled: Bool, punktoIsInstalled: Bool) -> MenuBarApp {
        if let chosen { return chosen }
        return !thawIsInstalled && punktoIsInstalled ? .punkto : .thaw
    }

    /// The one in use on this Mac now.
    @MainActor static func resolved(chosen: MenuBarApp?) -> MenuBarApp {
        resolved(chosen: chosen, thawIsInstalled: Thaw.applicationURL != nil, punktoIsInstalled: Punkto.applicationURL != nil)
    }
}
