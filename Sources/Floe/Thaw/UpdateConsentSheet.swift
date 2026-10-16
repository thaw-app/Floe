//
//  UpdateConsentSheet.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: plain English strings, and the sheet's presentation from Thaw's
//  SettingsWindow moved into a view modifier. The General page's toggle is Floe's.

import SwiftUI

struct UpdateConsentSheet: View {
    var onEnable: (_ autoDownload: Bool) -> Void
    var onDisable: () -> Void

    @State private var isProcessing = false
    @State private var autoDownload = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep \(AppInfo.displayName) up to date?")
                .font(.title2.bold())

            Text("\(AppInfo.displayName) can check for updates automatically. You can also check manually from the menu bar or Settings › About.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            Toggle(isOn: $autoDownload) {
                Text("Download and install updates automatically")
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Check Manually") {
                    guard !isProcessing else { return }
                    isProcessing = true
                    onDisable()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isProcessing)
                .buttonStyle(.settingsGlass)
                Button("Check Automatically") {
                    guard !isProcessing else { return }
                    isProcessing = true
                    onEnable(autoDownload)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}

// MARK: - Floe

/// Presents the consent sheet over the settings window while the manager asks for it.
private struct UpdateConsentModifier: ViewModifier {
    @Bindable var updatesManager: UpdatesManager

    func body(content: Content) -> some View {
        content.sheet(isPresented: $updatesManager.isConsentPresented) {
            UpdateConsentSheet { autoDownload in
                updatesManager.answerConsent(autoDownload ? .download : .check)
            } onDisable: {
                updatesManager.answerConsent(.off)
            }
            .interactiveDismissDisabled()
        }
    }
}

extension View {
    func updateConsentSheet(_ updatesManager: UpdatesManager) -> some View {
        modifier(UpdateConsentModifier(updatesManager: updatesManager))
    }
}

/// The General page's switch. Draws nothing in a build that cannot update.
struct AutomaticUpdateCheckToggle: View {
    @Bindable var updatesManager: UpdatesManager

    var body: some View {
        if updatesManager.isAvailable {
            Toggle("Automatically check for updates", isOn: $updatesManager.automaticallyChecksForUpdates)
        }
    }
}
