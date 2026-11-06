//
//  FileSearchModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The file search in the panel: its query and selection, and what is done with the selected file.
final class FileSearchModel: ObservableObject {
    @Published var query = "" {
        didSet {
            selection = 0
            isBrowsing = false
            spotlight.search(query)
        }
    }

    @Published var selection = 0
    /// Whether the arrows moved the selection since the text last changed: Space then previews the file instead of typing.
    private var isBrowsing = false
    /// Finds the files. It publishes its own results, which the view observes beside this model.
    let spotlight: FileSearch
    var host = ModeHost()
    /// The roles a file can be opened in, read each time the Actions menu is built.
    var preferredApps: () -> [RoleApp] = { [] }
    /// The user's choices of what Return, the Actions menu and keys do on a file, as in the root search.
    var alternatives = AlternativeActions()

    init(index: FileIndexService = .shared) {
        spotlight = FileSearch(index: index)
    }

    var selectedFile: FileResult? {
        spotlight.results.indices.contains(selection) ? spotlight.results[selection] : nil
    }

    /// Stops the query and empties the list, for when the search leaves the screen.
    func cancel() {
        spotlight.cancel()
    }

    /// What Return does on the selected file, as its button says.
    var returnTitle: String {
        selectedFile.flatMap { alternatives.returnTitle(for: .file($0)) } ?? Self.openTitle
    }

    private static var openTitle: String {
        String(localized: "Open", bundle: .floe, comment: "A button that opens the selected file.")
    }

    func openSelectedFile(flags: NSEvent.ModifierFlags = []) {
        guard let file = selectedFile else { return }
        activate(file, flags: flags)
    }

    /// Return on a file: what the user chose for its kind, when it applies, or else the file opens.
    func activate(_ file: FileResult, flags: NSEvent.ModifierFlags) {
        if alternatives.open(.file(file), flags: flags) {
            return
        }
        open(file)
    }

    /// Opens the file as Floe does, whatever the user chose.
    func open(_ file: FileResult) {
        spotlight.open(file)
        host.dismiss()
    }

    /// The keys on a file's rows: Floe's for its kind, with the user's laid over them. With no file selected, a
    /// file's, so they are still this search's and not typed into its field.
    func rowKeys(for file: FileResult?) -> ActionKeys {
        file.map { alternatives.keys(for: .file($0)) } ?? alternatives.keys(of: .file)
    }

    /// Runs one of the selected file's rows, as a button in the bottom bar does.
    func run(_ id: ActionID) {
        guard let file = selectedFile else { return }
        rows(for: file).compactMap(\.self).first { $0.id == id }?.run()
    }

    func actions(for file: FileResult) -> [ItemAction?] {
        let item = RootItem.file(file)
        let returnRow = ItemAction(title: alternatives.returnTitle(for: item) ?? Self.openTitle, symbol: "return") { [weak self] in self?.activate(file, flags: []) }
        return alternatives.menu(returnRow, rows: rows(for: file), for: item)
    }

    /// Floe's rows for a file and the user's scripts on it, with their keys, before the user's choices arrange the
    /// menu: a row the menu leaves out still runs by its keys.
    private func rows(for file: FileResult) -> [ItemAction?] {
        let actionHost = ActionHost(showHUD: host.showHUD, dismiss: host.dismiss, preferredApps: preferredApps())
        return alternatives.rows(FileActions.actions(for: file.url, host: actionHost), for: .file(file))
    }

    /// The panel's keys while this search is on screen. Returns true when the key was consumed.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, spotlight.results.count - 1))
            isBrowsing = true
            return true
        }
        if ActionKeys.handle(ActionKeys.pressed(event.keyCode, flags), keys: { rowKeys(for: selectedFile) }, rows: { selectedFile.map { rows(for: $0) } ?? [] }) {
            return true
        }
        switch event.keyCode {
        case 49 where flags.isEmpty && isBrowsing:
            guard let file = selectedFile else { return false }
            QuickLookPresenter.shared.show(file.url)
        case 36, 76:
            openSelectedFile(flags: flags)
        case 53:
            if query.isEmpty {
                host.close()
            } else {
                query = ""
            }
        case 40 where flags == .command:
            host.showActions()
        default: return false
        }
        return true
    }
}
