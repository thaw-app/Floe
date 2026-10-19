//
//  SettingsSidebarRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Foundation

/// A page in the settings sidebar, with the name and icon its row shows.
struct SettingsSidebarPage {
    let page: SettingsPage
    let label: SearchPaneLabel
    /// A disabled extension's row reads as off.
    var isDimmed = false
}

/// One row of the settings sidebar: a page to select, or the heading over a group of pages, in one flat list.
enum SettingsSidebarRow: Identifiable {
    case heading(String)
    case page(SettingsSidebarPage)

    var id: String {
        switch self {
        case let .heading(title): "heading:" + title
        case let .page(row): row.page.id
        }
    }

    /// The page a click selects; nil for a heading, which nothing selects.
    var page: SettingsPage? {
        if case let .page(row) = self {
            return row.page
        }
        return nil
    }
}

enum SettingsSidebarRows {
    /// Floe's basics first, then what search finds, then what Floe connects to, then each extension, About last.
    static func rows(commands: [ExtensionCommand], disabledExtensions: Set<String>) -> [SettingsSidebarRow] {
        let extensions = commands
            .uniqued(on: \.extensionName)
            .sorted { $0.extensionTitle.localizedCaseInsensitiveCompare($1.extensionTitle) == .orderedAscending }
            .map { command in
                SettingsSidebarRow.page(SettingsSidebarPage(
                    page: .extensionPage(command.extensionName),
                    label: SearchPaneLabel(title: command.extensionTitle, icon: command.icon ?? "icon:Terminal", assetsPath: command.assetsPath),
                    isDimmed: disabledExtensions.contains(command.extensionName)
                ))
            }
        let basics = pages([.general, .appearance, .privacy])
        let search = pages([.commands, .applications, .quicklinks, .snippets])
        let connections = pages([.ai, .sync, .extensionStore])
        return basics
            + [.heading(String(localized: "Search", bundle: .floe, comment: "A noun: the heading over the settings for searching."))] + search
            + [.heading(String(localized: "Connections", bundle: .floe, comment: "A heading in the settings sidebar, over the AI, Sync and Extension Store pages."))] + connections
            + (extensions.isEmpty ? [] : [.heading(String(localized: "Extensions", bundle: .floe, comment: "A heading in the settings sidebar, over the installed extensions."))] + extensions)
            + pages([.about])
    }

    private static func pages(_ panes: [SearchPane]) -> [SettingsSidebarRow] {
        panes.map { .page(SettingsSidebarPage(page: $0.page, label: $0.label)) }
    }
}
