//
//  Model+Runner.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

extension LauncherModel {
    /// Hands the runner what the panel does for a command.
    func connectRunner() {
        runner.host = ExtensionRunner.Host(
            showPanel: { [weak self] in self?.panelHost.showPanel() },
            hidePanel: { [weak self] in self?.panelHost.hidePanel() },
            showHUD: { [weak self] in self?.panelHost.showHUD($0) },
            refocus: { [weak self] in self?.focusToken += 1 },
            isPanelShown: { [weak self] in self?.isPanelShown ?? false },
            isWaitingToResume: { [weak self] in self?.isWaitingToResume ?? false },
            beginSetup: { [weak self] in self?.beginSetup($0) },
            toggleMenuBar: { [weak self] in self?.toggleMenuBarCommand($0) },
            runElsewhere: { [weak self] command, arguments in
                guard let present = self?.panelHost.presentInPanelProcess else { return false }
                present(.command(command.id, arguments: arguments.flatMap { try? JSONSerialization.data(withJSONObject: $0) }))
                return true
            },
            open: { [weak self] in self?.open($0, application: $1) },
            showPreferences: { [weak self] in self?.showPreferences($0, of: $1) },
            manifestChanged: { [weak self] in self?.catalog.reloadCommands() },
            clipboardHistory: { [weak self] in
                guard let self, settings.recordsClipboardHistory else { return [] }
                return clipboard.entries
            }
        )
    }

    private func open(_ target: String, application: String?) {
        let url = URL(string: target).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        if let application, let app = applicationURL(for: application) {
            linkOpener.open(url, app)
        } else if !runCommandLink(url) {
            openLink(url)
        }
    }

    /// Extensions name an app by path, bundle identifier or display name.
    private func applicationURL(for application: String) -> URL? {
        if (application as NSString).isAbsolutePath {
            return URL(fileURLWithPath: application)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: application)
            ?? catalog.apps.first { $0.name.caseInsensitiveCompare(application) == .orderedSame }?.url
    }
}
