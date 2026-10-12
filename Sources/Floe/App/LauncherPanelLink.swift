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
    private var appearance: AnyCancellable?

    init(model: LauncherModel, settingsLink: LauncherSettingsLink) {
        self.model = model
        self.settingsLink = settingsLink
    }

    func start() {
        let process = process
        model.presentInPanelProcess = { process.request($0) }
        model.showPanel = { process.request(.show) }
        model.hidePanel = { process.request(.hide) }
        model.showHUD = { process.request(.hud($0)) }
        ThawHUD.forward = { process.request(.hud($0)) }
        model.openSettings = { [settingsLink] in settingsLink.show(page: $0?.id) }
        IncomingURLRouter.shared.forwardOAuth = { process.request(.url($0)) }
        process.onMessage = { [weak self] in self?.receive($0) }
        process.onExit = { [settingsLink] in settingsLink.refreshFromPanel() }
        settingsLink.onChange = { process.send(.reload) }
        model.runningTimers.onChange = { [weak self] in
            guard let self else { return }
            process.send(.timers(self.model.runningTimers.all))
        }
        ClipboardHistoryStore.shared.onSnapshotSaved = { process.send(.clipboardChanged) }
        appearance = ThawAppearanceFollower.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { process.send(.appearance($0.rawValue)) }
    }

    private func receive(_ packet: PanelPacket) {
        switch packet {
        case .ready:
            process.send(.timers(model.runningTimers.all))
            process.send(.clipboardChanged)
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
        default: receiveStoreRequest(packet)
        }
    }

    private func receiveStoreRequest(_ packet: PanelPacket) {
        switch packet {
        case let .startTimer(draft): model.startTimer(draft)
        case let .stopTimer(id): _ = model.runningTimers.remove(id)
        case let .receipt(receipt):
            model.record(receipt)
            process.send(.refresh)
        case let .receiptUndone(id, date):
            model.receipts.markUndone(id, at: date)
            process.send(.refresh)
        case .clearClipboard: ClipboardHistoryStore.shared.clear()
        case let .deleteClipboard(id):
            if let entry = ClipboardHistoryStore.shared.entries.first(where: { $0.id == id }) {
                ClipboardHistoryStore.shared.delete(entry)
            }
        case let .pinClipboard(id):
            if let entry = ClipboardHistoryStore.shared.entries.first(where: { $0.id == id }) {
                ClipboardHistoryStore.shared.togglePin(entry)
            }
        default: break
        }
    }
}
