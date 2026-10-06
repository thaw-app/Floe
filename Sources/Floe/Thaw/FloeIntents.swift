//
//  FloeIntents.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  The structure of Thaw 3's App/Intents (ThawActionIntents, ApplyProfileIntent and
//  ActivateMenuBarItemIntent) with Floe's own intents: open the launcher, search the menu bar,
//  and run an extension command picked as an entity.

// Thin clients: perform() forwards to LauncherModel, the same calls the hotkeys make. An intent
// needing more than a few lines of dispatch belongs in the model first, and anything that decides
// which command is meant belongs in CommandLookup, which has tests.

import AppIntents
import AppKit

/// Shared lookup of the running model for every intent in this file. The system runs intents
/// inside the app's process, launching it if needed, so the delegate is there once the app has
/// finished launching; the conditional cast only covers launch ordering.
@MainActor
func floeModel() -> LauncherModel? {
    (NSApp?.delegate as? AppDelegate)?.model
}

/// Failure modes worth naming to the user.
enum FloeIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    /// Floe is not running, or is still coming up, so there is no model.
    case appNotReady
    /// The command was removed, or its extension switched off, after the shortcut was made.
    case commandNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            "Floe isn't running yet. Open Floe and try again."
        case .commandNotFound:
            "That command is no longer available in Floe."
        }
    }
}

// MARK: - Actions

struct OpenFloeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Floe"
    static let description: IntentDescription? = IntentDescription(
        "Show the Floe launcher.",
        categoryName: "Launcher"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = floeModel() else { throw FloeIntentError.appNotReady }
        model.showPanel()
        return .result()
    }
}

struct SearchMenuBarItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Menu Bar Items"
    static let description: IntentDescription? = IntentDescription(
        "Open Floe's search of the menu bar's items.",
        categoryName: "Launcher"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = floeModel() else { throw FloeIntentError.appNotReady }
        model.openMenuBarSearch()
        return .result()
    }
}

// MARK: - Commands

/// An extension command exposed to Shortcuts and Spotlight so a user can pick one to run.
/// The id is the command's "extension/command" key, the same one aliases and hotkeys use.
struct CommandEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Command"
    static let defaultQuery = CommandEntityQuery()

    var id: String
    var title: String
    var extensionTitle: String

    init(_ command: ExtensionCommand) {
        id = command.id
        title = command.title
        extensionTitle = command.extensionTitle
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: extensionTitle)
        )
    }
}

/// Lists the commands of the extensions that are switched on. The list lives in the running model,
/// so the query joins whatever catalog load is in flight on the main actor; when Floe is not ready
/// it returns nothing instead of failing.
struct CommandEntityQuery: EntityStringQuery {
    @MainActor
    static func runnableCommands() async -> [ExtensionCommand] {
        guard let model = floeModel() else { return [] }
        await model.waitForCommands()
        return CommandLookup.enabled(model.allCommands, disabledExtensions: AppSettings.shared.disabledExtensions, disabledCommands: AppSettings.shared.disabledCommands)
    }

    func entities(for identifiers: [String]) async throws -> [CommandEntity] {
        await CommandLookup.commands(withIDs: identifiers, in: Self.runnableCommands()).map(CommandEntity.init)
    }

    func entities(matching string: String) async throws -> [CommandEntity] {
        await CommandLookup.matching(string, in: Self.runnableCommands()).map(CommandEntity.init)
    }

    func suggestedEntities() async throws -> [CommandEntity] {
        await Self.runnableCommands().map(CommandEntity.init)
    }
}

/// Runs an extension command, the automation counterpart of a per-command hotkey. A command that
/// needs preferences or arguments asks for them in the launcher, as it does from the hotkey.
struct RunCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Command"
    static let description: IntentDescription? = IntentDescription(
        "Run an extension command in Floe.",
        categoryName: "Launcher"
    )

    @Parameter(title: "Command")
    var command: CommandEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = floeModel() else { throw FloeIntentError.appNotReady }
        let available = await CommandEntityQuery.runnableCommands()
        guard let match = CommandLookup.command(withID: command.id, in: available) else {
            throw FloeIntentError.commandNotFound
        }
        UsageStore.shared.recordUse(of: RootItem.command(match).id)
        model.run(match)
        return .result()
    }
}

// MARK: - Shortcut phrases

/// The App Shortcuts Floe publishes to Siri, Spotlight and the Shortcuts app.
///
/// Siri matches literally, hence several phrasings. A phrase without
/// \(.applicationName) is dropped at build time.
struct FloeShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor {
        .blue
    }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenFloeIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName)",
                "Show the \(.applicationName) launcher",
            ],
            shortTitle: "Open Floe",
            systemImageName: "command.square"
        )
        AppShortcut(
            intent: SearchMenuBarItemsIntent(),
            phrases: [
                "Search menu bar items in \(.applicationName)",
                "Search the menu bar with \(.applicationName)",
            ],
            shortTitle: "Search Menu Bar Items",
            systemImageName: "menubar.rectangle"
        )
        // Without parameterPresentation, an unspoken command has no options
        // to suggest and the phrase dead-ends.
        AppShortcut(
            intent: RunCommandIntent(),
            phrases: [
                "Run \(\.$command) in \(.applicationName)",
                "Run \(\.$command) with \(.applicationName)",
                "Run a command in \(.applicationName)",
            ],
            shortTitle: "Run Command",
            systemImageName: "play.rectangle",
            parameterPresentation: ParameterPresentation(
                for: \.$command,
                summary: Summary("Run \(\.$command)"),
                optionsCollections: {
                    OptionsCollection(
                        CommandEntityQuery(),
                        title: "Commands",
                        systemImageName: "puzzlepiece.extension"
                    )
                }
            )
        )
    }
}
