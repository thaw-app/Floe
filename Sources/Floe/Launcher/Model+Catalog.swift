//
//  Model+Catalog.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension LauncherModel {
    var commands: [ExtensionCommand] {
        CommandLookup.enabled(catalog.allCommands, disabledExtensions: settings.disabledExtensions, disabledCommands: settings.disabledCommands, enabledCommands: settings.enabledCommands)
    }

    /// Every command that may run on its own: a menu-bar command only once it was put in the menu bar.
    /// Controllers read this and filter by mode.
    var enabledCommands: [ExtensionCommand] {
        commands.filter { $0.mode != "menu-bar" || settings.menuBarCommands.contains($0.id) }
    }

    func isInMenuBar(_ command: ExtensionCommand) -> Bool {
        settings.menuBarCommands.contains(command.id)
    }

    /// Gives a menu-bar command its status item, or takes it away again.
    func toggleMenuBarCommand(_ command: ExtensionCommand) {
        if settings.menuBarCommands.remove(command.id) != nil {
            panelHost.showHUD(String(localized: "Removed from Menu Bar", bundle: .floe))
        } else {
            settings.menuBarCommands.insert(command.id)
            panelHost.showHUD(String(localized: "Added to Menu Bar", bundle: .floe))
        }
        refresh()
    }

    /// True when a command can run unattended: no missing required preferences, and every required argument given.
    func canRunUnattended(_ command: ExtensionCommand, arguments: [String: Any] = [:]) -> Bool {
        PreferenceStore.missingRequired(for: command).isEmpty
            && command.arguments.allSatisfy { !$0.required || arguments[$0.name] != nil }
    }

    /// Starts the first scans. Called after the panel and its subscriptions exist, so what they publish is heard.
    /// The resident loads what hotkeys and background work need, never what only the search reads.
    func startCatalogLoading() {
        catalog.reloadAll()
        if !isResident {
            catalog.reloadSettingsPanes()
        }
    }

    func catalogChanged(_ part: CatalogStore.Part) {
        switch part {
        case .apps:
            // What is installed decides the roles' fallbacks, so a change resolves them again.
            resolvedApps.invalidate()
            refresh()
        case .commands, .scripts:
            refresh()
        case .settingsPanes, .sshHosts:
            // Nothing to redraw without a query: these are only searched for.
            if !query.isEmpty {
                refresh()
            }
        }
    }
}
