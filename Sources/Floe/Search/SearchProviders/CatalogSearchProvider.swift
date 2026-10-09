//
//  CatalogSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Everything that is there whatever is typed: commands, scripts, apps, Floe's own rows,
/// system commands, snippets and note actions. System Settings' panes are only searched for.
struct CatalogSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        let builtIns: [RootItem] = [.menuBarSearch, .emojiSearch, ClipboardApps.row(for: context.clipboardDestination), .fileSearch, .settings]
        let found = context.commands.map(RootItem.command) + context.scripts.map(RootItem.script) + context.apps.map(RootItem.app)
        let own = builtIns + SystemCommand.allCases.map(RootItem.system) + context.snippets.map(RootItem.snippet)
            + context.notesApp.actions.filter(\.standsAlone).map { RootItem.note($0, text: "") } + context.thawActions.map(RootItem.thaw)
        return SearchContribution(ranked: found + own, searchOnly: context.settingsPanes.map(RootItem.settingsPane))
    }
}

/// The "Search Files for …" row that ends every search.
struct SearchFilesRowProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard !context.query.isEmpty else { return SearchContribution() }
        return SearchContribution(appended: [RootResult(item: .searchFiles(context.query), section: nil)])
    }
}
