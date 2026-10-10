//
//  ProcessLink.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Everything the launcher and its settings process tell each other. Each kind is one distributed
/// notification named after it, carrying the sender's pid and one short string.
struct LinkMessage: Equatable {
    enum Kind: String, CaseIterable {
        // Either way.

        /// `AppSettings` was saved: the other process reads it again from the defaults.
        case settingsChanged
        /// A store outside the settings was saved: the other process reads that one again. Payload: `LinkStore`.
        case storeChanged

        // Launcher to settings.

        /// Come to the front, on the page the payload names if it names one (see `SettingsPage.id`).
        case showPage
        /// What the launcher's updater reports. Payload: `UpdatesState`.
        case updatesState
        /// How the launcher's Thaw follower is doing. Payload: `ThawAppearanceFollower.Status`.
        case thawStatus
        /// How the launcher's index of file names is doing. Payload: `FileIndexService.State.text`.
        case fileIndexState
        /// How the launcher's settings sync is doing. Payload: `SyncStatus.text`.
        case syncState

        // Settings to launcher.

        /// The settings window is up: the launcher answers with `updatesState`, `thawStatus` and `fileIndexState`.
        case ready
        /// The page on screen, so the next opening starts there. Payload: `SettingsPage.id`.
        case pageChanged
        /// A hotkey recorder started ("1") or stopped ("0") listening: the launcher's hotkeys stand down meanwhile.
        case recording
        /// Something for the launcher's updater to do. Payload: `UpdateRequest`.
        case updates
        /// Settings added or removed scripts or extensions: the launcher scans them again. Payload: `LinkScan`.
        case rescan
        /// Clear History was pressed: the clipboard history lives in the launcher.
        case clearClipboardHistory
        /// A `floe://` link the system handed to the settings process instead of the launcher. Payload: the link.
        case forwardURL
        /// Remove Settings from iCloud was confirmed: the launcher holds the store.
        case removeSyncedSettings
        /// Quit was chosen in the settings process, which quits Floe as it did when Settings was a window of it.
        case quit

        var name: Notification.Name {
            Notification.Name("com.thaw.floe.link.\(rawValue)")
        }

        /// Whether a process in this role acts on the message: neither takes what only it would send.
        func isMeant(for role: ProcessLink.Role) -> Bool {
            switch self {
            case .settingsChanged, .storeChanged: true
            case .showPage, .updatesState, .thawStatus, .fileIndexState, .syncState: role == .settings
            case .ready, .pageChanged, .recording, .updates, .rescan, .clearClipboardHistory, .forwardURL, .removeSyncedSettings, .quit: role == .launcher
            }
        }
    }

    let kind: Kind
    let payload: String

    init(_ kind: Kind, _ payload: String = "") {
        self.kind = kind
        self.payload = payload
    }

    static let settingsChanged = LinkMessage(.settingsChanged)
    static let ready = LinkMessage(.ready)
    static let clearClipboardHistory = LinkMessage(.clearClipboardHistory)
    static let quit = LinkMessage(.quit)
    static let removeSyncedSettings = LinkMessage(.removeSyncedSettings)

    static func storeChanged(_ store: LinkStore) -> LinkMessage {
        LinkMessage(.storeChanged, store.rawValue)
    }

    static func rescan(_ scan: LinkScan) -> LinkMessage {
        LinkMessage(.rescan, scan.rawValue)
    }

    static func recording(_ isRecording: Bool) -> LinkMessage {
        LinkMessage(.recording, isRecording ? "1" : "0")
    }

    var store: LinkStore? {
        kind == .storeChanged ? LinkStore(rawValue: payload) : nil
    }

    var scan: LinkScan? {
        kind == .rescan ? LinkScan(rawValue: payload) : nil
    }

    var isRecording: Bool {
        kind == .recording && payload == "1"
    }

    /// False for a payload the kind does not take; such a message is dropped.
    var isWellFormed: Bool {
        switch kind {
        case .storeChanged: store != nil
        case .rescan: scan != nil
        case .recording: payload == "1" || payload == "0"
        case .settingsChanged, .ready, .clearClipboardHistory, .removeSyncedSettings, .quit: payload.isEmpty
        case .syncState: SyncStatus(text: payload) != nil
        case .showPage, .updatesState, .thawStatus, .fileIndexState, .pageChanged, .updates, .forwardURL: true
        }
    }
}

/// The stores both processes write, apart from `AppSettings`. Extension preferences are read from disk when needed,
/// so hearing of them only tells the launcher's sync to look.
enum LinkStore: String {
    case snippets, quicklinks, preferences
}

/// What the launcher scans again when Settings changed it on disk.
enum LinkScan: String {
    case scripts, commands
}

/// Whether a message is acted on: only one that names the other process of the pair as its sender.
/// The pid is the sender's own claim; a distributed notification carries no proof of where it came from.
struct LinkGate {
    let ownPid: Int32
    /// The launcher's settings process while it runs, or the settings process's launcher. Nil without one.
    let peerPid: () -> Int32?

    func accepts(sender: Int32?) -> Bool {
        guard let sender, sender != ownPid, let peer = peerPid() else { return false }
        return sender == peer
    }
}

/// One end of the link: posts this process's messages and hands over the other's.
final class ProcessLink: NSObject {
    enum Role {
        case launcher, settings
    }

    /// How messages travel. Tests pass their own, so nothing reaches the session's notification center.
    struct Transport {
        var post: (Notification.Name, [String: String]) -> Void
        var observe: (ProcessLink, Notification.Name) -> Void

        static let distributed = Transport(
            post: { name, info in
                // The other process reads the defaults when it hears this, so they are flushed first.
                CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
                DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
            },
            observe: { link, name in
                // The launcher is rarely the active app, and a held notification would arrive too late.
                DistributedNotificationCenter.default().addObserver(
                    link,
                    selector: #selector(ProcessLink.deliver(_:)),
                    name: name,
                    object: nil,
                    suspensionBehavior: .deliverImmediately
                )
            }
        )
    }

    /// The link of this process, once the launcher or the settings mode has made one. Nil in every other mode.
    static var current: ProcessLink?

    private static let pidKey = "pid"
    private static let payloadKey = "payload"

    let role: Role
    private let gate: LinkGate
    private let transport: Transport
    /// What a received message is handed to.
    var handler: (LinkMessage) -> Void = { _ in
        // Set by the owner before `start()`.
    }

    init(role: Role, gate: LinkGate, transport: Transport = .distributed) {
        self.role = role
        self.gate = gate
        self.transport = transport
    }

    func start() {
        for kind in LinkMessage.Kind.allCases where kind.isMeant(for: role) {
            transport.observe(self, kind.name)
        }
    }

    /// Does nothing while there is no other process to hear it.
    func send(_ message: LinkMessage) {
        guard gate.peerPid() != nil else { return }
        transport.post(message.kind.name, [Self.pidKey: String(gate.ownPid), Self.payloadKey: message.payload])
    }

    @objc private func deliver(_ notification: Notification) {
        let info = notification.userInfo?.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        // A distributed notification may arrive off the main thread; everything it touches is main-thread state.
        DispatchQueue.main.async { [weak self] in
            self?.receive(name: notification.name, info: info ?? [:])
        }
    }

    /// The message in a notification, when it is one this process should act on.
    func message(name: Notification.Name, info: [String: String]) -> LinkMessage? {
        guard let kind = LinkMessage.Kind.allCases.first(where: { $0.name == name }),
              kind.isMeant(for: role),
              gate.accepts(sender: info[Self.pidKey].flatMap(Int32.init)),
              let payload = info[Self.payloadKey]
        else { return nil }
        let message = LinkMessage(kind, payload)
        return message.isWellFormed ? message : nil
    }

    func receive(name: Notification.Name, info: [String: String]) {
        if let message = message(name: name, info: info) {
            handler(message)
        }
    }
}
