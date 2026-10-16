//
//  SettingsSearchContent.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchIndex {
    /// Every entry: Floe's own panes, then one group per installed extension.
    static func entries(commands: [ExtensionCommand]) -> [SearchEntry] {
        staticEntries + extensionEntries(for: commands)
    }
}
