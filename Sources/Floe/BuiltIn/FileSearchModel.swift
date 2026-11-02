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
    /// The kind of the file last asked about: the bottom bar and the preview ask on every draw, and a file's kind
    /// is read from the disk.
    private var lastKind: (url: URL, kind: SubjectKind?)?

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

    func openSelectedFile() {
        guard let file = selectedFile else { return }
        open(file)
    }

    func open(_ file: FileResult) {
        spotlight.open(file)
        host.dismiss()
    }

    /// Floe's keys on a file's rows, by its kind. With no file selected, a file's, so they are still this search's
    /// and not typed into its field.
    func rowKeys(for file: FileResult?) -> ActionKeys {
        guard let file else { return .floe(for: .file) }
        if let lastKind, lastKind.url == file.url {
            return .floe(for: lastKind.kind)
        }
        let kind = SubjectKind.of(file.url)
        lastKind = (file.url, kind)
        return .floe(for: kind)
    }

    /// Runs a row of the selected file's menu, as a button in the bottom bar does.
    func run(_ id: ActionID) {
        guard let file = selectedFile else { return }
        actions(for: file).compactMap(\.self).first { $0.id == id }?.run()
    }

    func actions(for file: FileResult) -> [ItemAction?] {
        let actionHost = ActionHost(showHUD: host.showHUD, dismiss: host.dismiss, preferredApps: preferredApps())
        return rowKeys(for: file).keyed([
            ItemAction(title: String(localized: "Open", bundle: .floe, comment: "A button that opens the selected file."), symbol: "return") { [weak self] in self?.openSelectedFile() },
        ] + FileActions.actions(for: file.url, host: actionHost))
    }

    /// The panel's keys while this search is on screen. Returns true when the key was consumed.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, spotlight.results.count - 1))
            isBrowsing = true
            return true
        }
        if ActionKeys.handle(ActionKeys.pressed(event.keyCode, flags), keys: { rowKeys(for: selectedFile) }, rows: { selectedFile.map { actions(for: $0) } ?? [] }) {
            return true
        }
        switch event.keyCode {
        case 49 where flags.isEmpty && isBrowsing:
            guard let file = selectedFile else { return false }
            QuickLookPresenter.shared.show(file.url)
        case 36, 76:
            openSelectedFile()
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
