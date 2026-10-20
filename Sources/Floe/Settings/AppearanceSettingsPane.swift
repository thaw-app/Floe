//
//  AppearanceSettingsPane.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Thaw's menu-bar appearance controls, applied to the launcher panel: glass, tint, border and shadow.
/// The preview draws them at miniature scale, so a change reads without summoning the panel.
struct AppearanceSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var follower: ThawAppearanceFollower
    @Environment(\.colorScheme) private var colorScheme
    @State private var thawIsInstalled = Thaw.applicationURL != nil

    private var mirror: ThawMirror? {
        settings.thawMirror(for: colorScheme)
    }

    /// The controls of a part Thaw supplies give way to a line saying so.
    private func follows(_ part: LauncherLookPart) -> Bool {
        mirror?.followed.contains(part) ?? false
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// A footnote whose text is already in the user's language.
    private func footnote(resolved text: String) -> some View {
        Text(verbatim: text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// The tint the single editor writes: light when the tints are separate,
    /// which is also the tint a static configuration draws.
    private var editing: Binding<LauncherTint> {
        Binding(
            get: { settings.launcherTintLight },
            set: { settings.launcherTintLight = $0 }
        )
    }

    private var editingDark: Binding<LauncherTint> {
        Binding(
            get: { settings.launcherTintDark },
            set: { settings.launcherTintDark = $0 }
        )
    }

    private var borderColor: Binding<Color> {
        Binding(
            get: { settings.launcherBorder.color.color },
            set: { settings.launcherBorder.color = StoredColor($0) }
        )
    }

    /// Following the system is its own flag, so the picker has one more choice than there are styles.
    private enum GlassChoice: Hashable {
        case matchSystem
        case style(LauncherGlassStyle)
    }

    private var glassChoice: Binding<GlassChoice> {
        Binding(
            get: { settings.launcherGlass.followsSystem ? .matchSystem : .style(settings.launcherGlass.style) },
            set: { choice in
                switch choice {
                case .matchSystem:
                    settings.launcherGlass.followsSystem = true
                case let .style(style):
                    settings.launcherGlass.followsSystem = false
                    settings.launcherGlass.style = style
                }
            }
        )
    }

    private func colorBinding(_ tint: Binding<LauncherTint>, _ keyPath: WritableKeyPath<LauncherGradient, StoredColor>) -> Binding<Color> {
        Binding(
            get: { tint.wrappedValue.gradient[keyPath: keyPath].color },
            set: { tint.wrappedValue.gradient[keyPath: keyPath] = StoredColor($0) }
        )
    }

    var body: some View {
        let look = settings.launcherLook(for: colorScheme)
        return Form {
            SettingsPageHeader()
            ThawSection("Preview") {
                LauncherAppearancePreview(
                    glass: look.glass,
                    tint: look.tint,
                    border: look.border,
                    hasShadow: look.hasShadow,
                    separateFieldShape: settings.separatesSearchField ? settings.searchFieldShape : nil
                )
                .frame(maxWidth: .infinity)
            }
            // Shown without Thaw too while it is on, so it can always be turned off.
            if thawIsInstalled || settings.followsThawAppearance {
                ThawSection("Thaw") {
                    Toggle("Follow Thaw's menu bar appearance", isOn: $settings.followsThawAppearance)
                    if settings.followsThawAppearance {
                        ForEach(ThawAppearanceNote.lines(status: follower.status, mirror: mirror), id: \.self) { footnote(resolved: $0) }
                    }
                }
            }
            ThawSection("Layout") {
                Picker("Launcher layout", selection: $settings.launcherLayout) {
                    ForEach(LauncherLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                footnote("Extended always shows the list. Compact shows only the search bar until you type.")
                Picker("Search field shape", selection: $settings.searchFieldShape) {
                    ForEach(SearchFieldShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Search field beam", selection: $settings.searchFieldBeam) {
                    ForEach(SearchFieldBeam.allCases) { beam in
                        Text(beam.title).tag(beam)
                    }
                }
                footnote("Light that sweeps around the inside of the search field's border.")
                if settings.searchFieldBeam != .off {
                    Slider(value: $settings.searchFieldBeamFrameRate, in: 15 ... 120, step: 15) {
                        Text("Beam frame rate")
                    } minimumValueLabel: {
                        Text("15 fps")
                    } maximumValueLabel: {
                        Text("120 fps")
                    }
                    footnote("\(Int(settings.searchFieldBeamFrameRate)) frames a second. Fewer are lighter on the graphics card; more are smoother.")
                }
                Toggle("Separate the search field from the results", isOn: $settings.separatesSearchField)
                footnote("The search field is its own piece of glass, and the results are a second piece below it.")
            }
            ThawSection("Glass") {
                if follows(.glass) {
                    footnote("The launcher is following Thaw's glass.")
                } else {
                    glassControls
                }
            }
            ThawSection("Tint") {
                if follows(.tint) {
                    footnote("The launcher is following Thaw's tint.")
                } else {
                    tintSection
                }
            }
            ThawSection("Border") {
                if follows(.border) {
                    footnote("The launcher is following Thaw's border.")
                } else {
                    borderControls
                }
            }
            ThawSection("Shadow") {
                if follows(.shadow) {
                    footnote("The launcher is following Thaw's shadow.")
                } else {
                    Toggle("Drop shadow", isOn: $settings.launcherShowsShadow)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var glassControls: some View {
        Picker("Effect", selection: glassChoice) {
            Text("Match System").tag(GlassChoice.matchSystem)
            ForEach(LauncherGlassStyle.allCases) { style in
                Text(style.title).tag(GlassChoice.style(style))
            }
        }
        .help("Match System follows Liquid Glass in System Settings → Appearance: Regular while it's Tinted, Clear while it's Clear.")
    }

    @ViewBuilder
    private var tintSection: some View {
        Toggle("Separate light and dark tints", isOn: $settings.launcherTintIsDynamic)
        if settings.launcherTintIsDynamic {
            tintControls("Light appearance", editing)
            tintControls("Dark appearance", editingDark)
        } else {
            tintControls("Tint", editing)
        }
    }

    @ViewBuilder
    private var borderControls: some View {
        Toggle("Draw a border", isOn: $settings.launcherShowsBorder)
        if settings.launcherShowsBorder {
            ColorPicker("Color", selection: borderColor, supportsOpacity: false)
            Slider(value: $settings.launcherBorder.width, in: 0.5 ... 4) {
                Text("Width")
            } minimumValueLabel: {
                Text("0.5 pt")
            } maximumValueLabel: {
                Text("4 pt")
            }
        }
    }

    @ViewBuilder
    private func tintControls(_ title: LocalizedStringKey, _ tint: Binding<LauncherTint>) -> some View {
        let solid = Binding(
            get: { tint.wrappedValue.solid.color },
            set: { tint.wrappedValue.solid = StoredColor($0) }
        )
        let opacity = Binding(
            get: { tint.wrappedValue.opacity },
            set: { tint.wrappedValue.opacity = $0 }
        )
        Picker(title, selection: tint.kind) {
            ForEach(LauncherTintKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        switch tint.wrappedValue.kind {
        case .none:
            EmptyView()
        case .solid:
            ColorPicker("Color", selection: solid, supportsOpacity: false)
        case .gradient:
            ColorPicker("Start color", selection: colorBinding(tint, \.start), supportsOpacity: false)
            ColorPicker("End color", selection: colorBinding(tint, \.end), supportsOpacity: false)
            Slider(value: tint.gradient.angle, in: 0 ... 360) {
                Text("Angle")
            } minimumValueLabel: {
                Text("0°")
            } maximumValueLabel: {
                Text("360°")
            }
        }
        if tint.wrappedValue.kind != .none {
            Slider(value: opacity, in: 0.05 ... 1) {
                Text("Opacity")
            } minimumValueLabel: {
                Text("5%")
            } maximumValueLabel: {
                Text("100%")
            }
        }
    }
}

/// A miniature launcher that runs the exact panel appearance pipeline, so the
/// glass, tint, border and shadow read live next to their controls.
struct LauncherAppearancePreview: View {
    let glass: LauncherGlass
    let tint: LauncherTint
    let border: LauncherBorder?
    let hasShadow: Bool
    /// The field's shape while the field is its own piece; nil draws the one panel.
    var separateFieldShape: SearchFieldShape?

    /// The miniature's pieces, at half the launcher's field and gap, over the two rows.
    private static let heights = PanelPieceHeights(field: 34, gap: ThawSpacing.tight, results: 60)

    var body: some View {
        if let separateFieldShape {
            VStack(spacing: Self.heights.gap) {
                field
                    .padding(.horizontal, 12)
                    .frame(height: Self.heights.field)
                    // At this scale a control's corner stands for the panel's.
                    .modifier(piece(radius: separateFieldShape.cornerRadius(height: Self.heights.field), style: separateFieldShape.pieceCornerStyle, facing: .bottom, span: Self.heights.fieldSpan))
                rows
                    .padding(12)
                    .frame(height: Self.heights.results)
                    .modifier(piece(radius: separateFieldShape.panelPieceRadius, style: .continuous, facing: .top, span: Self.heights.resultsSpan))
            }
            .padding(6)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                field
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quinary, in: Capsule(style: .continuous))
                rows
            }
            .padding(12)
            .modifier(LauncherPanelAppearance(glass: glass, tint: tint, border: border, hasShadow: hasShadow))
            .padding(6)
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Search")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewRow(width: 150)
            previewRow(width: 110)
        }
    }

    private func piece(radius: CGFloat, style: RoundedCornerStyle, facing: VerticalEdge, span: ClosedRange<CGFloat>) -> LauncherPanelAppearance {
        var appearance = LauncherPanelAppearance(glass: glass, tint: tint, border: border, hasShadow: hasShadow)
        appearance.cornerRadius = radius
        appearance.cornerStyle = style
        appearance.shadow = .piece(facing: facing)
        appearance.span = span
        return appearance
    }

    private func previewRow(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle().fill(.quinary).frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.quinary)
                .frame(width: width, height: 8)
            Spacer()
        }
    }
}

/// What the Appearance pane says under the switch while the launcher follows Thaw.
enum ThawAppearanceNote {
    static func lines(status: ThawAppearanceFollower.Status, mirror: ThawMirror?) -> [String] {
        [answer(status), wallpaper(mirror)].compactMap(\.self)
    }

    private static func answer(_ status: ThawAppearanceFollower.Status) -> String? {
        switch status {
        case .idle, .following:
            nil
        case .noAnswer:
            String(
                localized: "Thaw has not answered, so the launcher keeps the last look it had. A development build of Floe has to be allowed first: run \"\(ThawAction.authorize.title)\" from the search.",
                bundle: .floe,
                comment: "The placeholder is the name of a command in the search."
            )
        case .notRunning:
            String(localized: "Thaw is not running. The launcher keeps the last look it had and asks again when Thaw opens.", bundle: .floe)
        case .unreadable:
            String(localized: "Thaw answered in a form this version of Floe cannot read, so the launcher keeps the last look it had. Update Floe and Thaw.", bundle: .floe)
        }
    }

    /// Names the fills Thaw takes from the wallpaper, which carry no colour to copy.
    private static func wallpaper(_ mirror: ThawMirror?) -> String? {
        guard let mirror, !mirror.unmirrored.isEmpty else { return nil }
        // One whole sentence per case: the layers are named in Thaw's order, tint first.
        let isLeftOut = mirror.followed.contains(.tint)
        switch (mirror.unmirrored, isLeftOut) {
        case ([.tint], true): return String(localized: "Thaw's tint follows the wallpaper, which the launcher cannot copy, so it is left out.", bundle: .floe)
        case ([.tint], false): return String(localized: "Thaw's tint follows the wallpaper, which the launcher cannot copy, so the launcher keeps its own tint.", bundle: .floe)
        case ([.background], true): return String(localized: "Thaw's background follows the wallpaper, which the launcher cannot copy, so it is left out.", bundle: .floe)
        case ([.background], false): return String(localized: "Thaw's background follows the wallpaper, which the launcher cannot copy, so the launcher keeps its own tint.", bundle: .floe)
        case (_, true): return String(localized: "Thaw's tint and background follow the wallpaper, which the launcher cannot copy, so it is left out.", bundle: .floe)
        case (_, false): return String(localized: "Thaw's tint and background follow the wallpaper, which the launcher cannot copy, so the launcher keeps its own tint.", bundle: .floe)
        }
    }
}
