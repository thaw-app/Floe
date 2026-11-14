//
//  QuicklinksSearchEntries.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchIndex {
    static let quicklinksEntries: [SearchEntry] = [
        .quicklinks(
            "list",
            String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            section: String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            keywords: String(
                localized: "quicklink, keyword, link, name, url, list, edit, delete",
                bundle: .floe,
                comment: "Words that find the Quicklinks setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "new",
            String(localized: "New Quicklink", bundle: .floe),
            section: String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            keywords: String(
                localized: "new, add, create, quicklink",
                bundle: .floe,
                comment: "Words that find the New Quicklink setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "import",
            String(localized: "Import from Raycast…", bundle: .floe),
            section: String(localized: "Quicklinks", bundle: .floe, comment: "The name of a settings page."),
            keywords: String(
                localized: "import, raycast, rayconfig, export, backup, migrate",
                bundle: .floe,
                comment: "Words that find Import from Raycast in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "openWith",
            String(localized: "Open with", bundle: .floe),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "open with, app, browser, application",
                bundle: .floe,
                comment: "Words that find the Open with setting of a quicklink in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "name",
            String(localized: "Name", bundle: .floe, comment: "The label of the field for a name."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "name, title, label",
                bundle: .floe,
                comment: "Words that find the Name setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "keyword",
            String(localized: "Keyword", bundle: .floe, comment: "The word typed in the search to use a quicklink or a snippet."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "keyword, abbreviation, prefix, trigger",
                bundle: .floe,
                comment: "Words that find the Keyword setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "url",
            String(localized: "URL", bundle: .floe, comment: "The label of the field for a web address."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "url, link, address, query, template",
                bundle: .floe,
                comment: "Words that find the URL setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .quicklinks(
            "symbol",
            String(localized: "Symbol", bundle: .floe, comment: "The icon of a quicklink."),
            section: String(localized: "Quicklink", bundle: .floe, comment: "The heading of the form that edits one quicklink."),
            keywords: String(
                localized: "symbol, icon, glyph",
                bundle: .floe,
                comment: "Words that find the Symbol setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]
}
