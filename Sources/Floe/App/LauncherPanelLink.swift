//
//  LauncherPanelLink.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// Background ownership stays here: clipboard recording, usage writes, and countdowns have one
/// owner even while the foreground process is gone. Only snapshots and user requests cross the pipe.
final class LauncherPanelLink {
    let process = PanelProcess()
    private let model: LauncherModel
    private let settingsLink: LauncherSettingsLink
    private let clipboard: ClipboardHistoryStore
    private var appearance: AnyCancellable?

    /// Binds foreground requests to the resident model and its existing Settings owner.
    init(model: LauncherModel, clipboard: ClipboardHistoryStore, settingsLink: LauncherSettingsLink) {
        self.clipboard = clipboard
        self.model = model
        self.settingsLink = settingsLink
    }

    /// Installs forwarding and snapshot publishers without eagerly launching a foreground child.
    func start() {
        let process = process
        // The resident shows nothing itself: the panel process does, when asked.
        model.panelHost = PanelHost(
            hidePanel: { process.request(.hide) },
            showPanel: { process.request(.show) },
            showHUD: { process.request(.hud($0)) },
            openSettings: { [settingsLink] in settingsLink.show(page: $0?.id) },
            presentInPanelProcess: { process.request($0) }
        )
        IntentHandler.current = .serving(model) { process.request($0) }
        OAuthBroker.shared.say { process.request(.hud($0)) }
        IncomingURLRouter.shared.forwardOAuth = { process.request(.url($0)) }
        process.onMessage = { [weak self] in self?.receive($0) }
        process.onExit = { [settingsLink] in settingsLink.refreshFromPanel() }
        settingsLink.onChange = { process.send(.reload) }
        settingsLink.onRescan = { process.send(.rescan($0)) }
        model.features.timers.running.onChange = { [weak self] in
            guard let self else { return }
            process.send(.timers(self.model.features.timers.running.all))
        }
        clipboard.onSaved = { process.send(.clipboard($0)) }
        appearance = ThawAppearanceFollower.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { process.send(.appearance($0.rawValue)) }
    }

    /// Seeds a ready child and routes application-level requests back to their resident owners.
    private func receive(_ packet: PanelPacket) {
        switch packet {
        case .ready:
            process.send(.timers(model.features.timers.running.all))
            process.send(.clipboard(.reload))
            process.send(.appearance(ThawAppearanceFollower.shared.status.rawValue))
        case let .present(request): process.request(request)
        case let .openSettings(page): settingsLink.show(page: page)
        case let .settings(kind, payload):
            if let kind = LinkMessage.Kind(rawValue: kind) {
                settingsLink.receiveFromPanel(LinkMessage(kind, payload))
            }
        case .quit: NSApp.terminate(nil)
        case let .used(id): UsageStore.shared.recordUse(of: id)
        case let .query(query): UsageStore.shared.recordQuery(query)
        case let .launchInBackground(id, arguments, context): CommandLauncher.shared?.launchInBackground(id: id, arguments: arguments, context: context)
        default: receiveStoreRequest(packet)
        }
    }

    /// Applies timer, receipt and clipboard mutations once, using resident state rather than mirrors.
    private func receiveStoreRequest(_ packet: PanelPacket) {
        switch packet {
        case let .startTimer(draft): model.features.timers.startTimer(draft)
        case let .stopTimer(id): _ = model.features.timers.running.remove(id)
        case let .receipt(receipt):
            model.record(receipt)
            process.send(.refresh)
        case let .receiptUndone(id, date):
            model.features.receipts.store.markUndone(id, at: date)
            process.send(.refresh)
        case .clearClipboard: clipboard.clear()
        case let .deleteClipboard(id):
            if let entry = clipboard.entries.first(where: { $0.id == id }) {
                clipboard.delete(entry)
            }
        case let .pinClipboard(id):
            if let entry = clipboard.entries.first(where: { $0.id == id }) {
                clipboard.togglePin(entry)
            }
        default: break
        }
    }
}
