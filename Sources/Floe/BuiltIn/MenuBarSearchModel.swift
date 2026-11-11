//
//  MenuBarSearchModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

struct MenuBarResult: Identifiable {
    let extra: MenuBarExtra
    let section: String?
    var id: String {
        extra.id
    }
}

/// The menu bar item search in the panel: scanning, matching, renaming and clicking an item.
final class MenuBarSearchModel: ObservableObject {
    @Published var query = "" {
        didSet { refresh() }
    }

    @Published var results: [MenuBarResult] = []
    @Published var selection = 0
    @Published var isScanning = false
    @Published var accessGranted = MenuBarExtras.isTrusted
    /// The item being renamed with Edit Name, and the text typed so far.
    @Published var renamingItem: String?
    @Published var renameDraft = ""
    var extras: [MenuBarExtra] = []
    let recents: MenuBarSearchRecents
    var host = ModeHost()
    private let settings: AppSettings
    /// Asks for Accessibility and keeps checking until the answer is in. Tests pass their own.
    private let askForAccess: () -> Void

    init(
        settings: AppSettings,
        recents: MenuBarSearchRecents = MenuBarSearchRecents(),
        askForAccess: @escaping () -> Void = { AppPermissions.shared.accessibility.performRequest() }
    ) {
        self.settings = settings
        self.recents = recents
        self.askForAccess = askForAccess
    }

    /// Reads the menu bar once at launch, so the first search opens on a full list and not on a spinner.
    func warm() {
        guard MenuBarExtras.isTrusted, extras.isEmpty else { return }
        scan()
    }

    func scan() {
        accessGranted = MenuBarExtras.isTrusted
        guard accessGranted else {
            extras = []
            refresh()
            return
        }
        isScanning = extras.isEmpty
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let extras = MenuBarExtras.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.extras = extras
                isScanning = false
                refresh()
            }
        }
    }

    /// The grant happens in System Settings, however long that takes: `accessWasGranted` reads the menu bar then.
    func requestAccess() {
        askForAccess()
    }

    /// Accessibility was just granted, in the welcome window or in System Settings.
    func accessWasGranted() {
        scan()
    }

    /// No query: recently opened items, then every item in menu bar order. With a query: items whose
    /// name or owning app matches.
    func refresh() {
        selection = 0
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            let recent = recents.resolve(in: extras)
            let recentIDs = Set(recent.map(\.id))
            results = recent.map { MenuBarResult(extra: $0, section: String(localized: "Recent", bundle: .floe, comment: "The heading over the menu bar items opened lately.")) }
                + extras.filter { !recentIDs.contains($0.id) }.map { MenuBarResult(extra: $0, section: String(localized: "Menu Bar", bundle: .floe, comment: "The heading over every menu bar item.")) }
            return
        }
        results = MenuBarSearchScope.ranked(extras, query: query, names: settings.menuBarItemNames)
            .map { MenuBarResult(extra: $0, section: nil) }
    }

    /// The name the user gave the item, else the one its app reports.
    func displayName(for extra: MenuBarExtra) -> String {
        MenuBarSearchScope.displayName(for: extra, names: settings.menuBarItemNames)
    }

    var selectedExtra: MenuBarExtra? {
        results.indices.contains(selection) ? results[selection].extra : nil
    }

    func beginRenamingSelection() {
        guard let extra = selectedExtra else { return }
        renameDraft = displayName(for: extra)
        renamingItem = extra.id
    }

    /// An empty name goes back to the one the app reports.
    func commitRename() {
        guard let id = renamingItem else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespaces)
        settings.menuBarItemNames[id] = name.isEmpty ? nil : name
        renamingItem = nil
        let selected = selection
        refresh()
        selection = min(selected, max(results.count - 1, 0))
        host.refocus()
    }

    func cancelRename() {
        renamingItem = nil
        host.refocus()
    }

    /// Things Floe can do with an item; Thaw's moving between sections stays with Thaw.
    func actions(for extra: MenuBarExtra) -> [ItemAction?] {
        var actions: [ItemAction?] = [
            ItemAction(title: String(localized: "Click Item", bundle: .floe, comment: "A button that clicks the selected menu bar item."), symbol: "cursorarrow.click") { [weak self] in self?.open(extra) },
            ItemAction(title: String(localized: "Edit Name", bundle: .floe), symbol: "pencil") { [weak self] in self?.beginRenamingSelection() },
            ItemAction(title: String(localized: "Copy Name", bundle: .floe), symbol: "doc.on.doc") { [weak self] in
                guard let self else { return }
                NSPasteboard.general.copy(displayName(for: extra))
                host.showHUD(HUDText.copied(displayName(for: extra)))
            },
        ]
        if settings.menuBarItemNames[extra.id] != nil {
            actions.append(ItemAction(title: String(localized: "Restore Original Name", bundle: .floe), symbol: "arrow.uturn.backward") { [weak self] in
                self?.settings.menuBarItemNames[extra.id] = nil
                self?.refresh()
            })
        }
        if let url = extra.ownerURL {
            actions.append(nil)
            actions.append(ItemAction(title: String(localized: "Open \(extra.ownerName)", bundle: .floe, comment: "The placeholder is the name of an app."), symbol: "app") { [weak self] in
                NSWorkspace.shared.openWithoutWaiting(url)
                self?.host.hidePanel()
            })
            actions.append(ItemAction(title: String(localized: "Show \(extra.ownerName) in Finder", bundle: .floe, comment: "The placeholder is the name of an app."), symbol: "folder") { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self?.host.hidePanel()
            })
        }
        return actions
    }

    func open(_ extra: MenuBarExtra) {
        recents.record(extra.id)
        host.dismiss()
        // Pressed once the panel is gone, so the menu opens over the app the user came from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MenuBarExtras.open(extra) }
    }

    /// The panel's keys while this search is on screen. Returns true when the key was consumed.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if renamingItem != nil {
            return handleRenameKey(event)
        }
        if flags == .command, event.keyCode == 14 {
            beginRenamingSelection()
            return true
        }
        if flags == .command, event.keyCode == 40 {
            host.showActions()
            return true
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, results.count - 1))
            return true
        }
        switch event.keyCode {
        case 36, 76:
            if let extra = selectedExtra {
                open(extra)
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

    /// While a name is being typed, Return keeps it and Escape drops it; every other key is the field's.
    private func handleRenameKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: commitRename()
        case 53: cancelRename()
        default: return false
        }
        return true
    }
}
