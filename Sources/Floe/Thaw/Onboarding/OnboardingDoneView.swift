//
//  OnboardingDoneView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: how to open the launcher and find its keywords, Floe's shortcut and Launch at
//  Login, and the Raycast import that the tour offered before. Each choice applies at once, as in Settings.

import SwiftUI
import ThawUI

/// The last onboarding page: how to use Floe, and the settings worth choosing on day one.
struct OnboardingDoneView: View {
    @ObservedObject var settings: AppSettings
    let finishTitle: String
    let importFromRaycast: () -> Void
    let onFinish: () -> Void

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                Text("\(AppInfo.displayName) is ready", bundle: .floe, comment: "The placeholder is the name of this app.")
                    .font(ThawType.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: ThawSpacing.base) {
                    step("keyboard", Text("Press your shortcut from anywhere to open the launcher.", bundle: .floe))
                    step("questionmark.circle", Text("Type ? in the search to see every keyword.", bundle: .floe))
                }
                .frame(maxWidth: 440, alignment: .leading)
                .padding(.top, ThawSpacing.gutter)

                choices
                    .padding(.top, ThawSpacing.section)

                Button(action: importFromRaycast) {
                    Text("Import Raycast Quicklinks…", bundle: .floe)
                }
                .buttonStyle(.settingsGlass)
                .padding(.top, ThawSpacing.gutter)
            }
        } footer: {
            Spacer()
            OnboardingContinueButton(title: Text(verbatim: finishTitle), action: onFinish)
        }
    }

    private func step(_ symbol: String, _ text: Text) -> some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(ThawInk.supporting)
        }
        .font(ThawType.body)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.row) {
            HotkeyRecorder(
                keyCombination: $settings.toggleHotkey,
                onRecordingChange: { settings.isRecordingHotkey = $0 },
                label: { Text("Open \(AppInfo.displayName)", bundle: .floe, comment: "The placeholder is the name of this app.") }
            )
            // Outside a Form nothing caps its height, and its symbol grows to fill the page.
            .fixedSize(horizontal: false, vertical: true)
            LaunchAtLoginToggle(settings: settings)
                .toggleStyle(.thawCheckbox)
        }
        .padding(ThawSpacing.gutter)
        .frame(maxWidth: 440, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
