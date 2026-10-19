//
//  AITool.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A command line tool that can answer, named as it is typed in a terminal. The order is the one
/// Automatic looks in.
nonisolated enum AITool: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case opencode
    case pi

    var id: String {
        rawValue
    }

    /// The command, which is also the tool's name wherever Floe shows it.
    var command: String {
        rawValue
    }

    /// Whether Settings offers a model for it. Claude's is picked from what an extension asks for,
    /// and codex keeps the one in its own configuration.
    var takesModel: Bool {
        self == .opencode || self == .pi
    }
}

/// The picker for the tool in Settings: Automatic, the tools that are installed, and the chosen one when it has gone.
struct AIToolOption: Identifiable, Equatable {
    /// Nil is Automatic.
    let tool: AITool?
    let title: String

    var id: String {
        tool?.rawValue ?? "automatic"
    }

    static func options(chosen: AITool?, which: (String) -> URL?) -> [AIToolOption] {
        var options = [AIToolOption(tool: nil, title: String(localized: "Automatic", bundle: .floe, comment: "The choice that lets Floe pick the command line tool that answers."))]
        for tool in AITool.allCases {
            if which(tool.command) != nil {
                options.append(AIToolOption(tool: tool, title: tool.command))
            } else if tool == chosen {
                options.append(AIToolOption(tool: tool, title: String(localized: "\(tool.command) (not installed)", bundle: .floe, comment: "The placeholder is the name of a command line tool such as claude.")))
            }
        }
        return options
    }

    /// What Settings says when no tool can answer: the chosen one is missing, or none is installed.
    static func problem(chosen: AITool?) -> String {
        guard let chosen else { return String(localized: "AI can't answer yet. Install claude, codex, opencode or pi and sign in.", bundle: .floe, comment: "The names claude, codex, opencode and pi are commands and stay as written.") }
        return String(localized: "AI can't answer yet. \(chosen.command) is not installed. Install it and sign in, or choose another tool.", bundle: .floe, comment: "The placeholder is the name of a command line tool such as claude.")
    }
}

/// Which command line tool answers `AI.ask`. Floe has no models of its own: it uses a tool the
/// user has installed and signed in to, so the accounts and keys set up there are not asked for again.
nonisolated enum AIEngine {
    /// What Settings says about the tool: Automatic or one by name, and the model typed for each tool that takes one.
    struct Setup: Equatable, Sendable {
        /// Nil is Automatic.
        var tool: AITool?
        /// By `AITool.rawValue`.
        var models: [String: String] = [:]

        @MainActor
        init(_ settings: AppSettings) {
            tool = settings.aiTool
            models = settings.aiToolModels
        }

        init(tool: AITool? = nil, models: [String: String] = [:]) {
            self.tool = tool
            self.models = models
        }

        /// The model typed for a tool, as written; nil when the field is empty, which leaves the tool its own default.
        func model(for tool: AITool) -> String? {
            let model = (models[tool.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? nil : model
        }
    }

    static let missingMessage = String(localized: "AI needs a command line tool to answer: claude, codex, opencode or pi, installed and signed in.", bundle: .floe, comment: "The names claude, codex, opencode and pi are commands and stay as written.")

    /// Why there is no tool to ask, for the person who asked. A chosen tool that is missing is never replaced by another.
    static func missingMessage(for setup: Setup) -> String {
        guard let tool = setup.tool else { return missingMessage }
        return String(localized: "AI is set to answer with \(tool.command), which is not installed. Install it and sign in, or choose another tool under Settings › AI.", bundle: .floe, comment: "The placeholder is the name of a command line tool such as claude.")
    }

    /// Whether extensions should be told AI is there. The tools are looked up on the PATH known so far.
    @MainActor
    static var isAvailable: Bool {
        resolve(model: nil, setup: Setup(AppSettings.shared), which: { LoginEnvironment.which($0) }) != nil
    }

    /// A tool chosen by name is the only one tried. Automatic takes the first installed of claude, codex, opencode
    /// and pi, and codex first when the extension asked for an OpenAI model. `which` says what is installed.
    static func resolve(model: String?, setup: Setup = Setup(tool: nil), which: (String) -> URL?) -> TextGeneration.Engine? {
        func engine(_ tool: AITool) -> TextGeneration.Engine? {
            which(tool.command).map { executable in
                switch tool {
                case .claude: .claude(executable: executable, model: claudeModel(for: model))
                // Codex keeps the model the user configured: Raycast's names for OpenAI models are not Codex's.
                case .codex: .codex(executable: executable, model: nil)
                case .opencode: .opencode(executable: executable, model: setup.model(for: .opencode))
                case .pi: .pi(executable: executable, model: setup.model(for: .pi))
                }
            }
        }
        if let tool = setup.tool {
            return engine(tool)
        }
        let order = asksForOpenAI(model) ? [AITool.codex] + AITool.allCases.filter { $0 != .codex } : AITool.allCases
        for tool in order {
            if let found = engine(tool) {
                return found
            }
        }
        return nil
    }

    /// The Claude alias inside one of Raycast's model names ("Anthropic_Claude_Sonnet" gives "sonnet"),
    /// or nil to leave the choice to the engine.
    static func claudeModel(for requested: String?) -> String? {
        guard let name = requested?.lowercased() else { return nil }
        return ["opus", "sonnet", "haiku"].first { name.contains($0) }
    }

    private static func asksForOpenAI(_ model: String?) -> Bool {
        guard let name = model?.lowercased() else { return false }
        return name.contains("openai") || name.contains("gpt")
    }
}

nonisolated extension TextGeneration.Engine {
    var tool: AITool {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .opencode: .opencode
        case .pi: .pi
        }
    }

    /// The tool's name as the user types it in a terminal.
    var toolName: String {
        tool.command
    }
}
