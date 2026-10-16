//
//  RowHost.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What a row feature asks of the launcher. A feature that needs one or two things more keeps them beside it;
/// one that needs many has a host of its own.
struct RowHost {
    var showHUD: (String) -> Void = { _ in }
    var hidePanel: () -> Void = {}
    /// Hides the panel and goes back to the root search.
    var leave: () -> Void = {}
    /// Opens a link through the system once the panel is gone. Nil opens nothing.
    var reach: (URL?) -> Void = { _ in }
    /// Keeps a receipt of something Floe did, unless the user switched that off.
    var record: (Receipt) -> Void = { _ in }
    /// Reads the rows again, letting go of the scope on screen so its rows are read afresh.
    var rescan: () -> Void = {}
}
