//
//  ThawIntegration.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What Floe can ask Thaw to do, through the `thaw://` links Thaw 3 answers. The names are the
/// ones Thaw's own hotkey settings use, so an action reads the same in both apps.
enum ThawAction: String, CaseIterable, Identifiable {
    case toggleHidden
    case toggleAlwaysHidden
    case toggleSwap
    case search
    case itemHints
    case toggleThawBar
    case toggleApplicationMenus
    case toggleZenMode
    case toggleLayoutEditor
    case openSettings
    case toggleAutoRehide
    case toggleShowOnHover
    case toggleHideApplicationMenus
    case authorize

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .toggleHidden: String(localized: "Toggle the Hidden Section", bundle: .floe)
        case .toggleAlwaysHidden: String(localized: "Toggle the Always Hidden Section", bundle: .floe)
        case .toggleSwap: String(localized: "Swap Shown and Hidden Items", bundle: .floe)
        case .search: String(localized: "Search Menu Bar Items in Thaw", bundle: .floe)
        case .itemHints: String(localized: "Open an Item by Letter", bundle: .floe)
        case .toggleThawBar: String(localized: "Turn Thaw Bar On or Off", bundle: .floe)
        case .toggleApplicationMenus: String(localized: "Toggle Application Menus", bundle: .floe)
        case .toggleZenMode: String(localized: "Toggle Zen Mode", bundle: .floe)
        case .toggleLayoutEditor: String(localized: "Show Layout", bundle: .floe, comment: "A command that opens the layout editor of the app Thaw.")
        case .openSettings: String(localized: "Thaw Settings", bundle: .floe)
        case .toggleAutoRehide: String(localized: "Toggle Automatic Rehiding", bundle: .floe)
        case .toggleShowOnHover: String(localized: "Toggle Show on Hover", bundle: .floe)
        case .toggleHideApplicationMenus: String(localized: "Toggle Hiding Application Menus", bundle: .floe)
        case .authorize: String(localized: "Allow Floe to Change Thaw Settings", bundle: .floe)
        }
    }

    /// The path and query after `thaw://`, as Thaw 3's URL handler reads them.
    var link: String {
        switch self {
        case .toggleHidden: "toggle-hidden"
        case .toggleAlwaysHidden: "toggle-always-hidden"
        case .toggleSwap: "toggle-swap"
        case .search: "search"
        case .itemHints: "item-hints"
        case .toggleThawBar: "toggle-thawbar"
        case .toggleApplicationMenus: "toggle-application-menus"
        case .toggleZenMode: "toggle-zen-mode"
        case .toggleLayoutEditor: "toggle-layout-editor"
        case .openSettings: "open-settings"
        case .toggleAutoRehide: "toggle?key=autoRehide"
        case .toggleShowOnHover: "toggle?key=showOnHover"
        case .toggleHideApplicationMenus: "toggle?key=hideApplicationMenus"
        case .authorize: "authorize"
        }
    }

    var url: URL? {
        URL(string: "thaw://\(link)")
    }

    /// The three that change a setting only work once Thaw has Floe on its list of allowed apps.
    var changesASetting: Bool {
        switch self {
        case .toggleAutoRehide, .toggleShowOnHover, .toggleHideApplicationMenus: true
        default: false
        }
    }

    var keywords: [String] {
        let words = switch self {
        case .toggleHidden: String(localized: "thaw, menu bar, hidden, show hidden", bundle: .floe, comment: "Words that find the Toggle the Hidden Section command of the app Thaw, separated by commas.")
        case .toggleAlwaysHidden: String(localized: "thaw, menu bar, always hidden", bundle: .floe, comment: "Words that find the Toggle the Always Hidden Section command of the app Thaw, separated by commas.")
        case .toggleSwap: String(localized: "thaw, menu bar, swap", bundle: .floe, comment: "Words that find the Swap Shown and Hidden Items command of the app Thaw, separated by commas.")
        case .search: String(localized: "thaw, menu bar, find item", bundle: .floe, comment: "Words that find the Search Menu Bar Items in Thaw command of the app Thaw, separated by commas.")
        case .itemHints: String(localized: "thaw, item hints, letters", bundle: .floe, comment: "Words that find the Open an Item by Letter command of the app Thaw, separated by commas.")
        case .toggleThawBar: String(localized: "thaw, thawbar, bar", bundle: .floe, comment: "Words that find the Turn Thaw Bar On or Off command of the app Thaw, separated by commas.")
        case .toggleApplicationMenus: String(localized: "thaw, app menus, menus", bundle: .floe, comment: "Words that find the Toggle Application Menus command of the app Thaw, separated by commas.")
        case .toggleZenMode: String(localized: "thaw, zen, focus", bundle: .floe, comment: "Words that find the Toggle Zen Mode command of the app Thaw, separated by commas.")
        case .toggleLayoutEditor: String(localized: "thaw, edit layout, arrange", bundle: .floe, comment: "Words that find the Show Layout command of the app Thaw, separated by commas.")
        case .openSettings: String(localized: "thaw, preferences, open settings", bundle: .floe, comment: "Words that find the Thaw Settings command of the app Thaw, separated by commas.")
        case .toggleAutoRehide: String(localized: "thaw, rehide, auto hide", bundle: .floe, comment: "Words that find the Toggle Automatic Rehiding command of the app Thaw, separated by commas.")
        case .toggleShowOnHover: String(localized: "thaw, hover, reveal", bundle: .floe, comment: "Words that find the Toggle Show on Hover command of the app Thaw, separated by commas.")
        case .toggleHideApplicationMenus: String(localized: "thaw, hide menus", bundle: .floe, comment: "Words that find the Toggle Hiding Application Menus command of the app Thaw, separated by commas.")
        case .authorize: String(localized: "thaw, authorize, permission, automation", bundle: .floe, comment: "Words that find the Allow Floe to Change Thaw Settings command of the app Thaw, separated by commas.")
        }
        return words.keywordList
    }
}

enum Thaw {
    /// Where the app that answers `thaw://` links is, release or debug build; nil when none is installed.
    static var applicationURL: URL? {
        // Asked at every key and for every Thaw row drawn; an install or removal shows within a minute.
        located.value(for: 0, lasting: 60) {
            URL(string: "thaw://").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        }
    }

    private static let located = TimedCache<Int, URL?>()

    /// The actions to list: all of them with Thaw installed, none without.
    static func actions(isInstalled: Bool = applicationURL != nil) -> [ThawAction] {
        isInstalled ? ThawAction.allCases : []
    }

    /// Hands the link to Thaw and answers whether there was an app to take it.
    @discardableResult
    static func perform(_ action: ThawAction) -> Bool {
        guard let url = action.url, applicationURL != nil else { return false }
        return NSWorkspace.shared.open(url)
    }
}
