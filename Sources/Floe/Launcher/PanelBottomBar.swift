//
//  PanelBottomBar.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The Thaw-style bar under a list: what is on the left, then the selected row's actions with their keys.
struct PanelBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: ThawSpacing.row) {
            content
        }
        .buttonStyle(SearchPanelButtonStyle())
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
    }
}

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
