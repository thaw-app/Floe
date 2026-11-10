//
//  ActionsSearchEntries.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchPaneLabel {
    static let actions = SearchPaneLabel(title: String(localized: "Actions", bundle: .floe, comment: "The name of a settings page: what Return, the Actions menu and keys do on apps, files, folders, links and text."), symbol: "return")
}

extension SearchPane {
    static let actions = SearchPane(page: .actions, label: .actions)
}

extension SearchIndex {
    /// The Actions pane, found by its name, then its controls.
    static let actionsEntries: [SearchEntry] = [
        SearchEntry(
            id: "pane.actions",
            title: String(localized: "Actions", bundle: .floe, comment: "The name of a settings page: what Return, the Actions menu and keys do on apps, files, folders, links and text."),
            descriptionText: String(localized: "What Return does on apps, files, folders, links and text, which actions their Actions menu shows, and the keys that run them.", bundle: .floe),
            pane: .actions,
            keywords: String(
                localized: "actions, actions menu, primary action, return, enter, keys, keyboard shortcut",
                bundle: .floe,
                comment: "Words that find the Actions page in the settings search, separated by commas."
            ).searchTerms
        ),
        SearchEntry(
            id: "actions.actionChoices",
            title: String(localized: "Actions on Results", bundle: .floe, comment: "The heading over the choices of what Return, the Actions menu and keys do on apps, files, folders and links."),
            descriptionText: String(localized: "Choose what Return does on apps, files, folders and links, which actions their Actions menu shows, and keys that run an action.", bundle: .floe),
            pane: .actions,
            section: String(localized: "Actions on Results", bundle: .floe, comment: "The heading over the choices of what Return, the Actions menu and keys do on apps, files, folders and links."),
            keywords: String(
                localized: "return, enter, primary action, default action, actions menu, keys, keyboard shortcut, hide, show, apps, files, folders, links, open with, copy path, quick look",
                bundle: .floe,
                comment: "Words that find the Actions on Results setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]
}
