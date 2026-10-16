//
//  ThawAppearance.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import SwiftUI

/// The glass, tint, border and shadow the launcher panel draws.
struct LauncherLook: Equatable {
    var glass: LauncherGlass
    var tint: LauncherTint
    var border: LauncherBorder?
    var hasShadow: Bool
}

/// The parts of the launcher's look, as the Appearance pane groups them.
enum LauncherLookPart: Hashable {
    case glass
    case tint
    case border
    case shadow
}

/// Thaw's menu bar look for one colour scheme, as `thaw://get-appearance` answers it.
/// The menu bar's shape, its rounding and the border's dash style mean nothing to the launcher panel, so they are not read.
struct ThawAppearance: Codable, Equatable {
    static let supportedVersion = 1

    enum Scheme: String, Codable {
        case light
        case dark
    }

    /// Thaw's two fills: the tint is drawn over the background.
    enum Layer: String {
        case tint
        case background
    }

    /// sRGB components from 0 to 1.
    struct Color: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    struct Stop: Codable, Equatable {
        var color: Color
        var location: Double
    }

    /// The kind stays text, so one Thaw adds later is skipped instead of failing the whole answer.
    struct Fill: Codable, Equatable {
        var kind: String
        var opacity: Double
        var color: Color?
        var stops: [Stop]?
        var glassStyle: String?
        var glassIsColored: Bool?
    }

    struct Border: Codable, Equatable {
        var color: Color?
        var width: Double
    }

    var version: Int
    var colorScheme: Scheme
    var hasShadow: Bool
    /// Left out by Thaw when its border is off.
    var border: Border?
    var tint: Fill
    var background: Fill
}

/// Thaw's look laid over the launcher's own: what to draw, and which parts came from Thaw.
struct ThawMirror: Equatable {
    var look: LauncherLook
    var followed: Set<LauncherLookPart>
    /// Thaw's fills that follow the wallpaper and carry no colour, so they could not be copied.
    var unmirrored: [ThawAppearance.Layer]
}

extension ThawAppearance {
    /// Maps Thaw's look onto the launcher's. A part Thaw does not supply, or supplies in a kind
    /// that cannot be copied, stays as `own` has it.
    func mirrored(over own: LauncherLook) -> ThawMirror {
        var look = own
        var followed: Set<LauncherLookPart> = [.border, .shadow]
        look.hasShadow = hasShadow
        look.border = border.map { border in
            LauncherBorder(
                color: border.color.map(StoredColor.init) ?? own.border?.color ?? LauncherBorder().color,
                width: max(0, border.width)
            )
        }
        // The launcher has one glass and one tint: each takes Thaw's tint first, its background otherwise.
        if let glass = tint.glass(keeping: own.glass) ?? background.glass(keeping: own.glass) {
            look.glass = glass
            followed.insert(.glass)
        }
        let paints = [tint.paint(keeping: own.tint), background.paint(keeping: own.tint)]
        let chosen = paints[0] == .nothing ? paints[1] : paints[0]
        switch chosen {
        case let .tint(tint):
            look.tint = tint
            followed.insert(.tint)
        case .nothing:
            look.tint.kind = .none
            followed.insert(.tint)
        case .unmirrored:
            break
        }
        // Thaw's tint replaces the launcher's own, also when that one tints the glass.
        if followed.contains(.tint), !followed.contains(.glass) {
            look.glass.isColored = false
        }
        let unmirrored = zip([Layer.tint, .background], paints).filter { $0.1 == .unmirrored }.map(\.0)
        return ThawMirror(look: look, followed: followed, unmirrored: unmirrored)
    }
}

private extension ThawAppearance.Fill {
    enum Paint: Equatable {
        case tint(LauncherTint)
        /// No tint from this fill: it is off, or it is a glass.
        case nothing
        /// Adaptive, a kind added later, or a fill missing its colours.
        case unmirrored
    }

    func paint(keeping own: LauncherTint) -> Paint {
        var tint = own
        tint.opacity = opacity.clamped
        switch kind {
        case "none", "glass":
            return .nothing
        case "solid":
            guard let color else { return .unmirrored }
            tint.kind = .solid
            tint.solid = StoredColor(color)
        case "gradient":
            guard let gradient else { return .unmirrored }
            tint.kind = .gradient
            tint.gradient = gradient
        default:
            return .unmirrored
        }
        return .tint(tint)
    }

    /// The outermost two stops, at 90 degrees: Thaw draws its gradient from the menu bar's leading edge to its trailing one.
    var gradient: LauncherGradient? {
        let ordered = (stops ?? []).sorted { $0.location < $1.location }
        guard let first = ordered.first, let last = ordered.last else { return nil }
        return LauncherGradient(start: StoredColor(first.color), end: StoredColor(last.color), angle: 90)
    }

    /// Thaw's glass styles carry the names the launcher's do.
    func glass(keeping own: LauncherGlass) -> LauncherGlass? {
        guard kind == "glass", let style = glassStyle.flatMap(LauncherGlassStyle.init(rawValue:)) else { return nil }
        return LauncherGlass(
            style: style,
            followsSystem: false,
            isColored: glassIsColored ?? false,
            color: color.map(StoredColor.init) ?? own.color,
            opacity: opacity.clamped
        )
    }
}

private extension Double {
    var clamped: Double {
        min(max(self, 0), 1)
    }
}

extension StoredColor {
    init(_ color: ThawAppearance.Color) {
        self.init()
        red = color.red.clamped
        green = color.green.clamped
        blue = color.blue.clamped
        opacity = color.alpha.clamped
    }
}

/// Thaw's answer to `get-appearance`: the `thaw://get` envelope, as JSON in the callback's `data` parameter.
enum ThawAppearanceResponse {
    static let operation = "get-appearance"

    enum Rejection: Error, Equatable {
        case malformed
        case failed
        case unsupportedVersion
    }

    /// The part every answer has, read first to tell whose request it answers.
    struct Header: Decodable, Equatable {
        var requestId: String
        var operation: String
        var status: String
    }

    private struct Answer<Payload: Decodable>: Decodable {
        var data: Payload
    }

    private struct Version: Decodable {
        var version: Int
    }

    static func body(of url: URL) -> Data? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "data" }?.value
            .map { Data($0.utf8) }
    }

    static func header(of body: Data) -> Header? {
        try? JSONDecoder().decode(Header.self, from: body)
    }

    static func appearance(in body: Data) throws(Rejection) -> ThawAppearance {
        guard let header = header(of: body) else { throw .malformed }
        guard header.status == "success" else { throw .failed }
        // The version is read on its own: a later one may not decode as this one does.
        guard let versioned = try? JSONDecoder().decode(Answer<Version>.self, from: body) else { throw .malformed }
        guard versioned.data.version == ThawAppearance.supportedVersion else { throw .unsupportedVersion }
        guard let answer = try? JSONDecoder().decode(Answer<ThawAppearance>.self, from: body) else { throw .malformed }
        return answer.data
    }
}

extension AppSettings {
    /// The tint a view should draw for the given system appearance.
    func launcherTint(for colorScheme: ColorScheme) -> LauncherTint {
        guard launcherTintIsDynamic else { return launcherTintLight }
        return colorScheme == .dark ? launcherTintDark : launcherTintLight
    }

    /// The look the user set, whatever Thaw's is.
    func ownLauncherLook(for colorScheme: ColorScheme) -> LauncherLook {
        var glass = launcherGlass
        var tint = launcherTint(for: colorScheme)
        glass.isColored = false
        // A solid tint on a Liquid style washes the glass itself, as Thaw's tinted glass does.
        if tint.kind == .solid, glass.resolvedStyle().usesTint {
            glass.isColored = true
            glass.color = tint.solid
            glass.opacity = tint.opacity
            tint.kind = .none
        }
        return LauncherLook(
            glass: glass,
            tint: tint,
            border: launcherShowsBorder ? launcherBorder : nil,
            hasShadow: launcherShowsShadow
        )
    }

    /// Thaw's look for the scheme while the launcher follows it; nil when it does not, or Thaw has yet to answer.
    func thawMirror(for colorScheme: ColorScheme) -> ThawMirror? {
        guard followsThawAppearance else { return nil }
        let scheme: ThawAppearance.Scheme = colorScheme == .dark ? .dark : .light
        // Until Thaw answers for this scheme, its look for the other one is the closest there is.
        let appearance = thawAppearances[scheme] ?? thawAppearances.values.first
        return appearance?.mirrored(over: ownLauncherLook(for: colorScheme))
    }

    /// What the panel draws: Thaw's look while following it, the user's own otherwise.
    func launcherLook(for colorScheme: ColorScheme) -> LauncherLook {
        thawMirror(for: colorScheme)?.look ?? ownLauncherLook(for: colorScheme)
    }
}
