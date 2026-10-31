//
//  LauncherAppearance.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// A colour that survives settings persistence as sRGB components, so the
/// stored shape never depends on SwiftUI's own colour encoding.
struct StoredColor: Codable, Hashable {
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var opacity = 1.0

    init() {}

    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        opacity = Double(resolved.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// The app icon's gradient, where a chosen tint or glass colour starts. Settings saved without one read these.
    static let iconBlue = StoredColor(Color(red: 0.07, green: 0.40, blue: 0.90))
    static let iconNavy = StoredColor(Color(red: 0.02, green: 0.10, blue: 0.40))
}

/// How the launcher panel is tinted: Thaw's menu-bar tints, applied to the
/// launcher's glass instead of to the menu bar.
enum LauncherTintKind: String, Codable, CaseIterable, Identifiable {
    case none
    case solid
    case gradient

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .none: String(localized: "None (tint)", defaultValue: "None", bundle: .floe, comment: "A background tint choice: no tint.")
        case .solid: String(localized: "Solid", bundle: .floe, comment: "A background tint choice: one color.")
        case .gradient: String(localized: "Gradient", bundle: .floe, comment: "A background tint choice: two colors blended.")
        }
    }
}

/// A two-stop linear gradient by angle in degrees; 0 runs top to bottom.
///
/// The default stops are Floe's own: the blue gradient of the app icon
/// (bright blue into deep navy), so the starting palette is the brand's, not
/// a generic blue-to-purple.
struct LauncherGradient: Codable, Hashable {
    var start = StoredColor.iconBlue
    var end = StoredColor.iconNavy
    var angle = 180.0

    var style: AnyShapeStyle {
        let radians = angle * .pi / 180
        let start = UnitPoint(x: 0.5 - sin(radians) / 2, y: 0.5 - cos(radians) / 2)
        return AnyShapeStyle(LinearGradient(
            colors: [self.start.color, end.color],
            startPoint: start,
            endPoint: UnitPoint(x: 1 - start.x, y: 1 - start.y)
        ))
    }
}

/// The tint drawn behind the launcher's content, over the glass: the kind,
/// its colours, and how strongly it reads. The defaults are the app icon's
/// own gradient palette, so a chosen tint starts on the brand.
struct LauncherTint: Codable, Hashable {
    var kind = LauncherTintKind.none
    var solid = StoredColor.iconBlue
    var gradient = LauncherGradient()
    var opacity = 0.35

    /// The fill for the panel's shape, drawn between the glass and the
    /// content; nil when no tint is set.
    var backgroundStyle: AnyShapeStyle? {
        switch kind {
        case .none: nil
        case .solid: AnyShapeStyle(solid.color.opacity(opacity))
        case .gradient: AnyShapeStyle(gradient.style.opacity(opacity))
        }
    }
}

/// A stroke drawn around the launcher's rounded shape.
struct LauncherBorder: Codable, Hashable {
    var color = StoredColor(Color.white.opacity(0.6))
    var width = 1.0
}
