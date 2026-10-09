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
            spotlight.search(query)
        }
    }

    @Published var selection = 0
    /// Finds the files. It publishes its own results, which the view observes beside this model.
    let spotlight: FileSearch
    var host = ModeHost()
    /// The roles a file can be opened in, read each time the Actions menu is built.
    var preferredApps: () -> [RoleApp] = { [] }

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

    func revealSelectedFile() {
        guard let file = selectedFile else { return }
        spotlight.reveal(file)
        host.dismiss()
    }

    func copySelectedFilePath() {
        guard let file = selectedFile else { return }
        NSPasteboard.general.copy(file.url.path)
        host.showHUD(String(localized: "Copied", bundle: .floe, comment: "Said after something was copied."))
    }

    func actions(for file: FileResult) -> [ItemAction?] {
        let actionHost = ActionHost(showHUD: host.showHUD, dismiss: host.dismiss, preferredApps: preferredApps())
        return [
            ItemAction(title: String(localized: "Open", bundle: .floe, comment: "A button that opens the selected file."), symbol: "return") { [weak self] in self?.openSelectedFile() },
        ] + FileActions.actions(for: file.url, host: actionHost)
    }

    /// The panel's keys while this search is on screen. Returns true when the key was consumed.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, spotlight.results.count - 1))
            return true
        }
        switch event.keyCode {
        case 36 where flags == .command, 76 where flags == .command:
            revealSelectedFile()
        case 36, 76:
            openSelectedFile()
        case 53:
            if query.isEmpty {
                host.close()
            } else {
                query = ""
            }
        case 8 where flags == [.command, .shift]:
            copySelectedFilePath()
        case 40 where flags == .command:
            host.showActions()
        default: return false
        }
        return true
    }
}
