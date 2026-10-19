//
//  ExtensionAISource.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

nonisolated extension AIAnswer {
    /// The extension whose `AI.ask` is being answered; nil for Ask AI, which uses the choice on the AI page.
    @TaskLocal static var askingExtension: String?

    /// The source for one extension: the one it is pinned to, else the one chosen on the AI page.
    static func source(for extensionName: String?, pinned: [String: AISource], general: AISource) -> AISource {
        extensionName.flatMap { pinned[$0] } ?? general
    }

    /// The choice for one extension. A pinned API is the one set up on the AI page: there is one address and one key.
    @MainActor
    static func configured(for extensionName: String?, _ settings: AppSettings = .shared) -> Choice {
        let source = source(for: extensionName, pinned: settings.aiSourceByExtension, general: settings.aiSource)
        return choice(source: source, baseURL: settings.aiBaseURL, model: settings.aiModel) {
            Keychain.read(account: AIEndpoint.keychainAccount)
        }
    }

    /// Whether one extension should be told AI is there, with the source it is pinned to.
    @MainActor
    static func isAvailable(for extensionName: String?) -> Bool {
        isAvailable(
            choice: configured(for: extensionName),
            localOnly: AppSettings.shared.aiOnThisMacOnly,
            toolInstalled: { AIEngine.isAvailable },
            appleIntelligenceReady: { AppleIntelligence.problem == nil }
        )
    }
}

/// On an extension's settings page: the AI source its questions go to, when it is not the one on the AI page.
struct ExtensionAISourcePicker: View {
    @ObservedObject var settings: AppSettings
    let extensionName: String

    var body: some View {
        Picker(selection: Binding(
            get: { settings.aiSourceByExtension[extensionName] },
            set: { settings.aiSourceByExtension[extensionName] = $0 }
        )) {
            Text("The source chosen on the AI page").tag(AISource?.none)
            Divider()
            Text("The command line tool set up on the AI page").tag(AISource?.some(.tools))
            Text("The API set up on the AI page").tag(AISource?.some(.api))
            Text("Apple Intelligence, on this Mac").tag(AISource?.some(.appleIntelligence))
        } label: {
            Text("Answer its AI requests with")
            Text("For an extension that handles private text, a source on this Mac keeps its questions here.")
        }
    }
}
