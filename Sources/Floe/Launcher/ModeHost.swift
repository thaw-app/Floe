//
//  ModeHost.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What a mode's model asks of the launcher around it. The launcher model fills these in;
/// the defaults keep a mode's model usable on its own.
struct ModeHost {
    var showHUD: (String) -> Void = { _ in
        // No HUD.
    }

    var hidePanel: () -> Void = { /* no panel */ }
    /// Hides the panel and returns it to the root, as opening a result does.
    var dismiss: () -> Void = { /* no panel */ }
    /// Puts the keyboard back in the search field.
    var refocus: () -> Void = { /* no field */ }
    /// Leaves the mode for the root search.
    var close: () -> Void = { /* no root search */ }
    /// Opens or closes the Actions menu of the view on screen.
    var showActions: () -> Void = { /* no menu */ }
    /// Puts text into the app the user came from, as a snippet is pasted.
    var paste: (String) -> Void = { _ in
        // No app to paste into.
    }
}
