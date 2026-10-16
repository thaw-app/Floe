//
//  Model+Favorites.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension LauncherModel {
    func alias(for item: RootItem) -> String? {
        RootSearch.alias(for: item, aliases: settings.aliases)
    }

    func isFavorite(_ item: RootItem) -> Bool {
        settings.favorites.contains(item.id)
    }

    func toggleFavorite(_ item: RootItem) {
        if case .searchFiles = item {
            // The fallback row names a query, not a thing: it has no favorites entry.
            return
        }
        if item.isScopeResult {
            return
        }
        if case .askAI = item {
            return
        }
        if let index = settings.favorites.firstIndex(of: item.id) {
            settings.favorites.remove(at: index)
            panelHost.showHUD(String(localized: "Removed from Favorites", bundle: .floe))
        } else {
            settings.favorites.append(item.id)
            panelHost.showHUD(String(localized: "Added to Favorites", bundle: .floe))
        }
        refresh()
    }
}
