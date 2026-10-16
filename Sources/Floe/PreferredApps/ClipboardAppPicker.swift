//
//  ClipboardAppPicker.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// What keeps the clipboard history: Floe, nothing, a known app on this Mac, any app picked by hand, or a link.
struct ClipboardAppPicker: View {
    /// Stand for the rows that are not an app: Off, the link, and Choose, which opens a panel.
    private static let offID = "off"
    private static let linkID = "link"
    private static let chooseID = "choose"

    @ObservedObject var settings: AppSettings
    let installed: AppLookup

    /// The app stays listed while Floe or the link is chosen, so going back to it is one click.
    private var options: [AppOption] {
        PreferredApps.options(for: .clipboard, choice: settings.clipboardApp, installed: installed)
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                switch settings.clipboardHandler {
                case .floe where !settings.clipboardHistoryEnabled && !settings.clipboardHistoryIsParked: Self.offID
                case .floe: AppOption.defaultID
                case .app: settings.clipboardApp?.key ?? AppOption.defaultID
                case .link: Self.linkID
                }
            },
            set: { id in
                switch id {
                case Self.chooseID:
                    // The menu has to close before the panel can open.
                    DispatchQueue.main.async(execute: chooseApp)
                case Self.linkID:
                    settings.clipboardHandler = .link
                case Self.offID:
                    settings.clipboardHandler = .floe
                    settings.clipboardHistoryEnabled = false
                case AppOption.defaultID:
                    settings.clipboardHandler = .floe
                    settings.clipboardHistoryEnabled = true
                default:
                    guard let choice = options.first(where: { $0.id == id })?.choice else { return }
                    settings.clipboardApp = choice
                    settings.clipboardHandler = .app
                }
            }
        )
    }

    var body: some View {
        Picker(selection: selection) {
            ForEach(options) { option in
                Label {
                    Text(option.title)
                } icon: {
                    if let icon = PreferredAppPicker.icon(for: option) {
                        Image(nsImage: icon)
                    }
                }
                .tag(option.id)
            }
            if !settings.clipboardHistoryIsParked {
                Text("Off").tag(Self.offID)
            }
            Divider()
            Text(ClipboardApps.linkTitle).tag(Self.linkID)
            Text("Choose…").tag(Self.chooseID)
        } label: {
            Text(AppRole.clipboard.title)
            Text(AppRole.clipboard.detail)
        }
        if settings.clipboardHandler == .link {
            TextField(text: $settings.clipboardURL, prompt: Text(verbatim: ClipboardApps.links["com.raycast.macos"] ?? "")) {
                Text("Link")
                Text("The link that opens your clipboard app's history.")
            }
        }
        // Stays whatever is chosen: the copies saved before are still on disk.
        LabeledContent("Clipboard history") {
            // The history is the launcher's: it is the one that watches the clipboard.
            Button("Clear History") { ProcessLink.current?.send(.clearClipboardHistory) }
        }
    }

    private func chooseApp() {
        guard let path = ModalGuard.chooseApp() else { return }
        settings.clipboardApp = PreferredApps.choice(forAppAt: URL(fileURLWithPath: path), installed: installed)
        settings.clipboardHandler = .app
    }
}
