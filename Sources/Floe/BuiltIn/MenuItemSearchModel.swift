//
//  MenuItemSearchModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The front app's menu commands in the panel: reading its menus, matching them and choosing one.
final class MenuItemSearchModel: ObservableObject {
    /// What the search asks of the system. Tests pass their own: no Accessibility, no other app.
    struct Environment {
        var frontApp: () -> MenuTarget? = { MenuItems.frontApp() }
        var isTrusted: () -> Bool = { MenuBarExtras.isTrusted }
        /// Asks for Accessibility and keeps checking until the answer is in.
        var askForAccess: () -> Void = { AppPermissions.shared.accessibility.performRequest() }
        var scan: @Sendable (pid_t) -> [AppMenuItem] = MenuSearchScanner.entries
        var choose: (AppMenuItem, MenuTarget) -> Void = { MenuItems.choose($0, in: $1) }
    }

    @Published var query = "" {
        didSet { refresh() }
    }

    @Published private(set) var results: [AppMenuItem] = []
    @Published var selection = 0
    @Published private(set) var isScanning = false
    @Published private(set) var accessGranted: Bool
    /// The app whose menus these are. Nil when Floe itself was in front.
    let target: MenuTarget?
    var host = ModeHost()
    /// The read in flight, which a test waits for.
    private(set) var scanning: Task<Void, Never>?
    private var entries: [AppMenuItem] = []
    private let environment: Environment

    /// The app in front now is the one whose menus are read.
    init(environment: Environment = Environment()) {
        target = environment.frontApp()
        self.environment = environment
        accessGranted = environment.isTrusted()
    }

    /// Reads the app's menus off the main thread: each item is a round trip to the app, and a busy app answers slowly.
    func scan() {
        accessGranted = environment.isTrusted()
        guard accessGranted, let target else {
            entries = []
            refresh()
            return
        }
        isScanning = true
        let scan = environment.scan
        scanning?.cancel()
        scanning = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { scan(target.pid) }.value
            guard let self, !Task.isCancelled else { return }
            entries = found
            isScanning = false
            refresh()
        }
    }

    func requestAccess() {
        environment.askForAccess()
    }

    func refresh() {
        selection = 0
        results = MenuItems.ranked(entries, query: query.trimmingCharacters(in: .whitespaces))
    }

    var selectedEntry: AppMenuItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// The panel goes first, so the command acts on the app and not on the launcher.
    func choose(_ entry: AppMenuItem) {
        guard let target else { return }
        host.dismiss()
        environment.choose(entry, target)
    }

    /// The panel's keys while this search is on screen. Returns true when the key was consumed.
    func handleKey(_ event: NSEvent, _: NSEvent.ModifierFlags) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, results.count - 1))
            return true
        }
        switch event.keyCode {
        case 36, 76:
            if let entry = selectedEntry {
                choose(entry)
            }
        case 53:
            if query.isEmpty {
                host.close()
            } else {
                query = ""
            }
        default: return false
        }
        return true
    }
}
