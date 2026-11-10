//
//  LauncherAppearance.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import ThawUI

/// The launcher's look is ThawUI's, which holds no text: what its choices are called in Settings is said here.
extension LauncherTintKind {
    var title: String {
        switch self {
        case .none: String(localized: "None (tint)", defaultValue: "None", bundle: .floe, comment: "A background tint choice: no tint.")
        case .solid: String(localized: "Solid", bundle: .floe, comment: "A background tint choice: one color.")
        case .gradient: String(localized: "Gradient", bundle: .floe, comment: "A background tint choice: two colors blended.")
        }
    }
}

extension LauncherGlassStyle {
    var title: String {
        switch self {
        case .regular: String(localized: "Regular", bundle: .floe, comment: "A kind of glass material for the launcher, as a choice in a picker.")
        case .clear: String(localized: "Clear", bundle: .floe, comment: "A kind of glass material for the launcher, as a choice in a picker.")
        case .liquid: String(localized: "Liquid Glass", bundle: .floe, comment: "A kind of glass material for the launcher, as a choice in a picker.")
        case .dynamic: String(localized: "Dynamic Glass", bundle: .floe, comment: "A kind of glass material for the launcher, as a choice in a picker.")
        }
    }
}
