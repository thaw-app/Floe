//
//  MenuBarCommands.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// The part of a status item a menu-bar command uses; tests stand in for it.
@MainActor protocol MenuBarStatusItem: AnyObject {
    var statusButton: (any MenuBarStatusButton)? { get }
    var menu: NSMenu? { get set }
}

extension NSStatusItem: MenuBarStatusItem {
    var statusButton: (any MenuBarStatusButton)? {
        button
    }
}

/// What menu-bar commands need from the system: the menu bar, extension hosts and icon files.
@MainActor struct MenuBarHost {
    var addItem: () -> any MenuBarStatusItem = { NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
    var removeItem: (any MenuBarStatusItem) -> Void = { item in
        if let item = item as? NSStatusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    var start: (ExtensionSession) -> Void = { $0.start() }
    var resolver: (_ assetsPath: String) -> MenuBarIconResolver = { MenuBarIconResolver.system(assetsPath: $0) }
    var icons = IconThumbnailCache.shared
}

/// One menu-bar command's status item and its running session.
@MainActor final class MenuBarCommands {
    private let model: LauncherModel
    private let host: MenuBarHost
    private let images: MenuBarIconImages
    private var entries: [String: Entry] = [:]
    /// The setting as it was last read: a command that has joined it since was put there by the user.
    private var inMenuBar: Set<String>

    /// How long a session that was sent a click while its successor started is left to finish the work.
    static let handoverGrace: TimeInterval = 10

    private final class Entry {
        let item: any MenuBarStatusItem
        let presenter: MenuBarPresenter
        var command: ExtensionCommand
        var session: ExtensionSession?
        /// The session whose render is on screen, which is the one before the current session until that one has drawn.
        var shown: ExtensionSession?
        /// Whether a row was clicked while the session before was on screen.
        var shownIsBusy = false
        /// A session that is no longer on screen and is finishing the click it was sent.
        var finishing: ExtensionSession?
        var cancellables = Set<AnyCancellable>()
        init(item: any MenuBarStatusItem, presenter: MenuBarPresenter, command: ExtensionCommand) {
            self.item = item
            self.presenter = presenter
            self.command = command
        }
    }

    init(model: LauncherModel, host: MenuBarHost? = nil) {
        let host = host ?? MenuBarHost()
        self.model = model
        self.host = host
        self.inMenuBar = model.settings.menuBarCommands
        self.images = MenuBarIconImages(cache: host.icons)
    }

    func presenter(for id: String) -> MenuBarPresenter? {
        entries[id]?.presenter
    }

    func session(for id: String) -> ExtensionSession? {
        entries[id]?.session
    }

    /// Keeps one status item plus one running session per enabled menu-bar command.
    func sync(_ commands: [ExtensionCommand]) {
        let wanted = commands.filter { $0.mode == "menu-bar" }
        let ids = Set(wanted.map(\.id))
        let added = model.settings.menuBarCommands.subtracting(inMenuBar)
        inMenuBar = model.settings.menuBarCommands
        for id in entries.keys where !ids.contains(id) {
            remove(id)
        }
        for command in wanted {
            if let entry = entries[command.id] {
                entry.command = command
                entry.presenter.commandTitle = command.title
            } else {
                start(command, launchType: added.contains(command.id) ? "userInitiated" : "background")
            }
        }
    }

    /// Stops and restarts one command's session, for interval refreshes. The status item stays and
    /// shows the last render until the new session has one, so the menu bar does not blink each time.
    func refresh(_ command: ExtensionCommand) {
        guard let entry = entries[command.id] else { return }
        entry.command = command
        entry.presenter.commandTitle = command.title
        run(entry)
    }

    func stopAll() {
        for id in entries.keys {
            remove(id)
        }
    }

    private func start(_ command: ExtensionCommand, launchType: String) {
        let item = host.addItem()
        let resolver = host.resolver
        let presenter = MenuBarPresenter(button: item.statusButton, commandTitle: command.title, images: images) { [weak self] in
            resolver(self?.entries[command.id]?.command.assetsPath ?? command.assetsPath)
        }
        let entry = Entry(item: item, presenter: presenter, command: command)
        entry.presenter.onAction = { [weak entry] nodeID in
            guard let entry, let session = entry.shown, let node = session.root?.descendant(id: nodeID) else { return }
            entry.shownIsBusy = session !== entry.session
            session.event(node, "onAction", [["type": "left-click"]])
        }
        entry.presenter.onOpen = { [weak self, weak entry] in
            // A session that has not drawn yet is already the run this opening would ask for, and one
            // that failed is started again with Try Again.
            guard let self, let entry, entry.shown === entry.session, entry.session?.failure == nil else { return }
            run(entry, launchType: "userInitiated", keepsShown: true)
        }
        entry.presenter.onRetry = { [weak self, weak entry] in
            guard let self, let entry else { return }
            // Asked for by hand, so the menu says it is loading instead of showing what failed.
            entry.presenter.show(root: nil)
            run(entry)
        }
        entry.presenter.onRemove = { [weak self, weak entry] in
            guard let self, let entry else { return }
            model.toggleMenuBarCommand(entry.command)
        }
        item.menu = entry.presenter.menu
        entries[command.id] = entry
        run(entry, launchType: launchType)
    }

    /// Gives the entry a fresh session, ending the one it had. With keepsShown, the one on screen runs on
    /// until the new one has drawn, so a row clicked in between still reaches the session that drew it.
    private func run(_ entry: Entry, launchType: String = "background", keepsShown: Bool = false) {
        entry.cancellables.removeAll()
        if !keepsShown {
            stop(entry)
        }
        let session = ExtensionSession(command: entry.command, launchType: launchType)
        session.onMessage = { [weak self] message in
            self?.model.runner.handleBackgroundMessage(message)
        }
        let presenter = entry.presenter
        presenter.show(failure: nil)
        // Published in willSet, so the value handed over is the new one while the property is still the old.
        // The first value is the empty state every session starts in, which is not a render.
        session.$root.dropFirst().sink { [weak self, weak entry, weak session, weak presenter] in
            self?.handOver(entry, to: session)
            presenter?.show(root: $0)
        }.store(in: &entry.cancellables)
        session.$failure.dropFirst().sink { [weak self, weak entry, weak session, weak presenter] in
            if $0 != nil {
                self?.handOver(entry, to: session)
            }
            presenter?.show(failure: $0)
        }.store(in: &entry.cancellables)
        entry.session = session
        host.start(session)
    }

    /// Puts the given session on screen and ends the one that was, at once unless it has a click to finish.
    private func handOver(_ entry: Entry?, to session: ExtensionSession?) {
        guard let entry, let session, entry.shown !== session else { return }
        let last = entry.shown
        entry.shown = session
        guard entry.shownIsBusy else {
            last?.forceStop()
            return
        }
        entry.shownIsBusy = false
        entry.finishing?.forceStop()
        entry.finishing = last
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handoverGrace) { [weak entry, weak last] in
            last?.forceStop()
            if entry?.finishing === last {
                entry?.finishing = nil
            }
        }
    }

    private func stop(_ entry: Entry) {
        entry.session?.forceStop()
        entry.shown?.forceStop()
        entry.finishing?.forceStop()
        entry.shown = nil
        entry.finishing = nil
        entry.shownIsBusy = false
    }

    private func remove(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.cancellables.removeAll()
        stop(entry)
        entry.session = nil
        entry.item.menu = nil
        host.removeItem(entry.item)
    }
}
