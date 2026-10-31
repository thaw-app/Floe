//
//  WelcomeSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Settings → General: a way back to the welcome window. The permissions themselves are on the Privacy page.
struct WelcomeSettingsSection: View {
    let showWelcome: () -> Void

    var body: some View {
        ThawSection(.floe("Welcome")) {
            LabeledContent {
                Button("Show Welcome") { showWelcome() }
                    .buttonStyle(.settingsGlass)
            } label: {
                Text("Welcome window")
                Text("The introduction from the first launch.")
            }
        }
    }
}
