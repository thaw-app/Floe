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
    @State private var tab = AppearanceTab.layout

    private var mirror: ThawMirror? {
        settings.thawMirror(for: colorScheme)
    }

    /// The controls of a part Thaw supplies give way to a line saying so.
    private func follows(_ part: LauncherLookPart) -> Bool {
        mirror?.followed.contains(part) ?? false
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(ThawType.footnote)
            .foregroundStyle(ThawInk.supporting)
    }

    /// A footnote whose text is already in the user's language.
    private func footnote(resolved text: String) -> some View {
        Text(verbatim: text)
            .font(ThawType.footnote)
            .foregroundStyle(ThawInk.supporting)
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
                .padding(.vertical, ThawSpacing.gutter)
                // Glass over the form's card would show nothing behind it; this stands in for a desktop.
                .background(PreviewBackdrop(), in: RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
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
            SettingsTabs(selection: $tab)
            switch tab {
            case .layout: layoutSection
            case .glass: glassSections
            case .edges: edgeSections
            }
        }
        .formStyle(.grouped)
    }

    private var layoutSection: some View {
        ThawSection("Layout") {
            LabeledContent {
                ThawPillPicker(selection: $settings.launcherLayout, values: LauncherLayout.allCases, title: \.title)
                    .accessibilityLabel(Text("Launcher layout"))
            } label: {
                Text("Launcher layout")
                Text("Extended always shows the list. Compact shows only the search bar until you type.")
            }
            LabeledContent("Search field shape") {
                ThawPillPicker(selection: $settings.searchFieldShape, values: SearchFieldShape.allCases, title: \.title)
                    .accessibilityLabel(Text("Search field shape"))
            }
            ThawPicker(selection: $settings.searchFieldBeam) {
                ForEach(SearchFieldBeam.allCases) { beam in
                    Text(beam.title).tag(beam)
                }
            } label: {
                Text("Search field beam")
                Text("Light that sweeps around the inside of the search field's border.")
            }
            if settings.searchFieldBeam != .off {
                LabeledContent {
                    ThawSlider(value: $settings.searchFieldBeamFrameRate, in: 15 ... 120, step: 15) {
                        Text(verbatim: "\(Int(settings.searchFieldBeamFrameRate)) fps")
                            .monospacedDigit()
                    }
                } label: {
                    Text("Beam frame rate")
                    Text("Fewer frames are lighter on the graphics card; more are smoother.")
                }
            }
            Toggle(isOn: $settings.separatesSearchField) {
                Text("Separate the search field from the results")
                Text("The search field is its own piece of glass, and the results are a second piece below it.")
            }
        }
    }

    @ViewBuilder private var glassSections: some View {
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
    }

    @ViewBuilder private var edgeSections: some View {
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

    private var glassControls: some View {
        ThawPicker("Effect", selection: glassChoice) {
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
            LabeledContent("Width") {
                ThawSlider(value: $settings.launcherBorder.width, in: 0.5 ... 4) {
                    Text(verbatim: "\(settings.launcherBorder.width.formatted(.number.precision(.fractionLength(0 ... 1)))) pt")
                        .monospacedDigit()
                }
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
        LabeledContent(title) {
            ThawPillPicker(selection: tint.kind, values: LauncherTintKind.allCases, title: \.title)
                .accessibilityLabel(Text(title))
        }
        switch tint.wrappedValue.kind {
        case .none:
            EmptyView()
        case .solid:
            ColorPicker("Color", selection: solid, supportsOpacity: false)
        case .gradient:
            ColorPicker("Start color", selection: colorBinding(tint, \.start), supportsOpacity: false)
            ColorPicker("End color", selection: colorBinding(tint, \.end), supportsOpacity: false)
            LabeledContent("Angle") {
                ThawSlider(value: tint.gradient.angle, in: 0 ... 360) {
                    Text(verbatim: "\(Int(tint.wrappedValue.gradient.angle))°")
                        .monospacedDigit()
                }
            }
        }
        if tint.wrappedValue.kind != .none {
            LabeledContent("Opacity") {
                ThawSlider(value: opacity, in: 0.05 ... 1) {
                    Text(opacity.wrappedValue, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
            }
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

/// The Appearance page's tabs, under the preview: the launcher's layout, its glass and tint, and its border and shadow.
nonisolated enum AppearanceTab: SettingsTab {
    case layout
    case glass
    case edges

    init?(entry id: String) {
        switch id {
        case "appearance.glassEffect", "appearance.tintStyle", "appearance.tintColor", "appearance.tintOpacity": self = .glass
        case "appearance.border", "appearance.shadow": self = .edges
        case _ where id.hasPrefix("appearance."): self = .layout
        default: return nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .layout: "Layout"
        case .glass: "Glass and Tint"
        case .edges: "Border and Shadow"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: "rectangle.split.1x2"
        case .glass: "drop"
        case .edges: "square.dashed"
        }
    }
}
