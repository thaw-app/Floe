//
//  ThawTheme+Floe.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

extension ThawTheme {
    /// Floe keeps the accent off its rows: a selected one is a soft gray with a faint edge, and the hover is neutral.
    static let floe = ThawTheme(
        selection: .flat(fill: .primary.opacity(0.1), edge: .primary.opacity(0.08)),
        hoverTint: .primary
    )
}
