//
//  PreferredAppActions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

extension FileActions {
    /// "Open in Ghostty", "Open in Zed": one row per role, named after the app the role stands for.
    static func preferredAppActions(for url: URL, host: ActionHost) -> [ItemAction] {
        host.preferredApps.compactMap { entry in
            guard let handoff = PreferredApps.handoff([url], to: entry.app, role: entry.role, isFolder: PreferredApps.isFolder) else {
                return nil
            }
            let icon = NSWorkspace.shared.icon(forFile: entry.app.url.path)
            icon.size = NSSize(width: 16, height: 16)
            return ItemAction(title: String(localized: "Open in \(entry.app.name)", bundle: .floe, comment: "The placeholder is the name of an app."), symbol: "arrow.up.forward.app", icon: icon) {
                PreferredApps.open(handoff)
                host.dismiss()
            }
        }
    }
}

extension LauncherModel {
    /// Opens what is selected in Finder, or the front window's folder, in a role's app.
    func openFinderSelection(in role: AppRole, app: ResolvedApp) {
        hidePanel()
        reset()
        PanelWork.perform { [self] in
            do {
                let items = try await FinderSelection.selectionOrFolder()
                if let handoff = PreferredApps.handoff(items, to: app, role: role, isFolder: PreferredApps.isFolder) {
                    PreferredApps.open(handoff)
                }
            } catch SelectionError.automationRefused {
                SystemCommand.askForAutomation(toControl: "Finder")
            } catch {
                showHUD(String(localized: "Couldn't read the Finder selection", bundle: .floe))
            }
        }
    }
}
