//
//  Model+FileSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Showing and leaving the file search; the search itself is `FileSearchModel`.
extension LauncherModel {
    /// Switches the panel to the file search, starting with the given text.
    func openFileSearch(with text: String) {
        runner.endOpenCommand()
        setup = nil
        isSearchingFiles = true
        fileSearch.query = text
        panelHost.showPanel()
        focusToken += 1
    }

    func closeFileSearch() {
        isSearchingFiles = false
        fileSearch.cancel()
        focusToken += 1
    }
}
