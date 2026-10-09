//
//  AISettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// General's AI section: what answers an extension's `AI.ask`.
struct AISettingsSection: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKey: String
    @State private var service: AIService

    /// `storedKey` is the Keychain's unless a snapshot passes its own.
    init(settings: AppSettings, storedKey: String? = Keychain.read(account: AIEndpoint.keychainAccount)) {
        self.settings = settings
        _apiKey = State(initialValue: storedKey ?? "")
        _service = State(initialValue: AIService.matching(settings.aiBaseURL))
    }

    /// The choice as it stands in the fields, with the key typed here and not the stored one.
    private var choice: AIAnswer.Choice {
        AIAnswer.choice(source: settings.aiSource, baseURL: settings.aiBaseURL, model: settings.aiModel) { apiKey }
    }

    var body: some View {
        ThawSection("AI") {
            Picker(selection: $settings.aiSource) {
                Text("A command line tool you are signed in to").tag(AISource.tools)
                Text("An OpenAI-compatible API").tag(AISource.api)
                Text("Apple Intelligence, on this Mac").tag(AISource.appleIntelligence)
            } label: {
                Text("Answer AI requests with")
                Text("Extensions that ask AI a question get their answer from here.")
            }
            if choice != .api(nil), AIAnswer.refusal(for: choice, localOnly: settings.aiOnThisMacOnly) != nil {
                warning(String(localized: "This source is not on this Mac, and Privacy allows only AI that runs on this Mac. Nothing is asked until one of them changes.", bundle: .floe))
            }
            switch settings.aiSource {
            case .tools:
                toolRows
            case .appleIntelligence:
                if let problem = AppleIntelligence.problem {
                    warning(problem)
                } else {
                    LabeledContent("Model") {
                        Text("Runs on this Mac. Nothing is sent anywhere.").foregroundStyle(.secondary)
                    }
                }
            case .api:
                Picker("Service", selection: $service) {
                    ForEach(AIService.allCases) { service in
                        Text(service.title).tag(service)
                    }
                }
                .onChange(of: service) { _, service in
                    if let address = service.baseURL {
                        settings.aiBaseURL = address
                    }
                }
                if service == .other {
                    TextField("Address", text: $settings.aiBaseURL, prompt: Text(AIEndpoint.defaultBaseURL))
                }
                TextField("Model", text: $settings.aiModel, prompt: Text("The model's name, as the API lists it"))
                // A server on this Mac takes no key, so the field would only invite a wrong one.
                if AIEndpoint.needsKey(AIEndpoint.chatURL(baseURL: settings.aiBaseURL)) {
                    SecureField("API key", text: $apiKey, prompt: Text("Kept in the Keychain"))
                        .onChange(of: apiKey) { _, key in
                            if key.isEmpty {
                                Keychain.delete(account: AIEndpoint.keychainAccount)
                            } else {
                                Keychain.write(key, account: AIEndpoint.keychainAccount)
                            }
                        }
                }
                if let problem = AIEndpoint.problem(baseURL: settings.aiBaseURL, model: settings.aiModel, apiKey: apiKey) {
                    warning(problem)
                }
            }
        }
    }

    /// The tool that answers, where it is, and its model when it takes one.
    @ViewBuilder private var toolRows: some View {
        let which: (String) -> URL? = { LoginEnvironment.which($0) }
        Picker(selection: $settings.aiTool) {
            ForEach(AIToolOption.options(chosen: settings.aiTool, which: which)) { option in
                Text(option.title).tag(option.tool)
            }
        } label: {
            Text("Tool")
            Text("Automatic uses the first one installed: claude, codex, opencode, then pi. Accounts and keys stay in the tool.")
        }
        if let engine = AIEngine.resolve(model: nil, setup: AIEngine.Setup(settings), which: which) {
            LabeledContent("Path") {
                Text(engine.executable.path).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if engine.tool.takesModel {
                TextField("Model", text: toolModel(engine.tool), prompt: Text("provider/model, or empty for the default set in \(engine.toolName)"))
            }
        } else {
            warning(AIToolOption.problem(chosen: settings.aiTool))
        }
    }

    private func toolModel(_ tool: AITool) -> Binding<String> {
        Binding {
            settings.aiToolModels[tool.rawValue] ?? ""
        } set: { model in
            settings.aiToolModels[tool.rawValue] = model.isEmpty ? nil : model
        }
    }

    /// The text stays in the label color, which red body text does not match for contrast; the symbol carries the red.
    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
