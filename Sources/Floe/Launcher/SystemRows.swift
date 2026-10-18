//
//  SystemRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What acts on the Mac itself: system commands, panes of System Settings, Thaw's actions and SSH hosts.
final class SystemRows {
    var host = RowHost()
    /// Plays, pauses or skips the music, for the commands that control it.
    var controlMusic: (MusicCommand) -> Void = { _ in
        // Set by LauncherFeatures.
    }
    /// How a host's connection is opened. Tests replace it, so they open nothing.
    var sshConnector = SSHConnector.system

    /// Risky commands ask first; the panel goes away before anything runs.
    func run(_ command: SystemCommand) {
        host.leave()
        if let question = command.confirmation {
            guard Confirm.destructive(command.title, detail: question, button: command.title) else { return }
        }
        if let flip = command.flip {
            host.showHUD(flip())
            return
        }
        if let control = command.music {
            controlMusic(control)
            return
        }
        command.perform { [weak self] in self?.host.showHUD($0) }
    }
}

extension SystemRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case .sshHost = item else { return nil }
        return String(localized: "Connect", bundle: .floe, comment: "A verb on a button: open an SSH connection to the host.")
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case let .system(command):
            run(command)
        case let .settingsPane(pane):
            host.leave()
            if let url = pane.url {
                NSWorkspace.shared.openWithoutWaiting(url)
            }
        case let .thaw(action):
            host.leave()
            if !Thaw.perform(action) {
                host.showHUD(String(localized: "Thaw isn't installed", bundle: .floe))
            }
        case let .sshHost(sshHost, terminal):
            host.leave()
            SSHConnection.connect(to: sshHost, terminal: terminal, using: sshConnector) { [weak self] in self?.host.showHUD($0) }
        default:
            return false
        }
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .sshHost(sshHost, _) = item else { return nil }
        return SSHHostActions.actions(for: sshHost, host: ActionHost(showHUD: host.showHUD, dismiss: host.leave))
    }
}
