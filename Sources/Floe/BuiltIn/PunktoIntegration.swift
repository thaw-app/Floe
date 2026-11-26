//
//  PunktoIntegration.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What Floe can ask Punkto to do, through the punkto:// links it answers. Each one shows or hides
/// the apps already chosen in Punkto and changes nothing saved there.
enum PunktoAction: String, CaseIterable, Identifiable {
    case toggle
    case show
    case hide

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .toggle: String(localized: "Show or Hide the Hidden Apps", bundle: .floe, comment: "A command of the app Punkto, which hides the menu bar items of apps the user chose.")
        case .show: String(localized: "Show the Hidden Apps", bundle: .floe, comment: "A command of the app Punkto, which hides the menu bar items of apps the user chose.")
        case .hide: String(localized: "Hide the Apps Again", bundle: .floe, comment: "A command of the app Punkto, which hides the menu bar items of apps the user chose.")
        }
    }

    /// The link Punkto's handler reads: the action's name is the whole request.
    var url: URL? {
        URL(string: "punkto://\(rawValue)")
    }

    var keywords: [String] {
        let words = switch self {
        case .toggle: String(localized: "punkto, menu bar, hidden apps, toggle", bundle: .floe, comment: "Words that find the Show or Hide the Hidden Apps command of the app Punkto, separated by commas.")
        case .show: String(localized: "punkto, menu bar, hidden apps, reveal", bundle: .floe, comment: "Words that find the Show the Hidden Apps command of the app Punkto, separated by commas.")
        case .hide: String(localized: "punkto, menu bar, hide apps", bundle: .floe, comment: "Words that find the Hide the Apps Again command of the app Punkto, separated by commas.")
        }
        return words.keywordList
    }
}

enum Punkto {
    /// Where the app that answers punkto:// links is; nil when none is installed.
    static var applicationURL: URL? {
        // Asked at every key and for every Punkto row drawn; an install or removal shows within a minute.
        located.value(for: 0, lasting: 60) {
            URL(string: "punkto://").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        }
    }

    private static let located = TimedCache<Int, URL?>()

    /// The actions to list: all of them with Punkto installed, none without.
    static func actions(isInstalled: Bool = applicationURL != nil) -> [PunktoAction] {
        isInstalled ? PunktoAction.allCases : []
    }

    /// Hands the link to Punkto and answers whether there was an app to take it. Tests pass their own opener.
    @discardableResult
    static func perform(
        _ action: PunktoAction,
        isInstalled: Bool = applicationURL != nil,
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        guard let url = action.url, isInstalled else { return false }
        return open(url)
    }
}
