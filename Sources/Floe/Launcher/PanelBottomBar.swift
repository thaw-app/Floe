//
//  PanelBottomBar.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The gear at the left of a bottom bar. It takes the style of the bar it sits in.
struct OpenSettingsButton: View {
    let model: LauncherModel

    var body: some View {
        Button {
            model.panelHost.hidePanel()
            model.panelHost.openSettings(nil)
        } label: {
            Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(ThawSpacing.hairline)
        }
        // Its own style, not the bar's: the gear is resizable and fills any bar that forgets to set one.
        .buttonStyle(SearchPanelButtonStyle())
        .help("Open Settings")
        .accessibilityLabel("Open Settings")
    }
}

/// The Actions button of a search. Its menu hangs off the button, so the button has to be reachable as an AppKit view.
struct ActionsButton: View {
    let model: LauncherModel
    let actions: (LauncherModel) -> [ItemAction?]

    var body: some View {
        ShortcutHintButton(title: String(localized: "Actions…", bundle: .floe)) { model.panelHost.showActions() } hint: {
            KeyCapView(text: "⌘")
            KeyCapView(text: "K")
        }
        .background { ActionsAnchor(model: model, actions: actions) }
    }
}

/// Keys as caps in a hint, read from where they are kept instead of written out: ⇧ ⌘ F, or ⌘ and the Return glyph.
struct KeyCaps: View {
    let keys: KeyCombination

    var body: some View {
        ForEach(Array(keys.modifiers.symbolicValue), id: \.self) { symbol in
            KeyCapView(text: String(symbol))
        }
        if keys.key == .returnKey {
            KeyCapView(systemImage: "return")
        } else {
            KeyCapView(text: keys.key.stringValue.uppercased())
        }
    }
}
