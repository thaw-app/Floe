//
//  CheckpointRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What saving and resuming a checkpoint reach outside the launcher through. Tests replace its parts.
struct CheckpointEnvironment {
    /// What is selected in Finder, or the folder in front. Empty when Finder may not be asked.
    var finderItems: @Sendable () async -> [URL] = { await (try? FinderSelection.selectionOrFolder()) ?? [] }
    /// The tabs open in the browsers Floe can ask.
    var tabs: @Sendable () async -> [BrowserTab] = {
        await BrowserTabs.read(BrowserApp.all.filter(BrowserApp.isRunning), run: AppleScript.run).tabs
    }

    /// Opens a file in its own app, or a folder in Finder.
    var openFile: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Opens files in the app a role stands for.
    var openIn: (Handoff) -> Void = { PreferredApps.open($0) }
    var confirmsDelete: (Checkpoint) -> Bool = { checkpoint in
        Confirm.destructive(
            String(localized: "Delete the checkpoint “\(checkpoint.name)”?", bundle: .floe, comment: "The placeholder is the name the user gave a checkpoint."),
            detail: String(localized: "Its files and tabs are not touched. Only the list of them goes.", bundle: .floe),
            button: String(localized: "Delete", bundle: .floe)
        )
    }
}

/// Checkpoints, as the launcher saves and resumes them.
final class CheckpointRows {
    /// What checkpoints ask of the launcher.
    struct Host {
        var hidePanel: () -> Void = {}
        var showHUD: (String) -> Void = { _ in }
        /// Hides the panel and goes back to the root search.
        var leave: () -> Void = {}
        var record: (Receipt) -> Void = { _ in }
        /// Shows text in the output window.
        var showOutput: (_ title: String, _ text: String) -> Void = { _, _ in }
        /// Opens a link in the browser the role says.
        var openLink: (URL) -> Void = { _ in }
        /// The editor the user chose for text and code, if any.
        var chosenEditor: () -> ResolvedApp? = { nil }
    }

    var environment = CheckpointEnvironment()
    var host = Host()
    var store = CheckpointStore.shared
    /// The saved checkpoints, read when the launcher opens and when one is saved or deleted.
    private(set) var checkpoints: [Checkpoint] = []

    func reload() {
        checkpoints = store.all
    }

    /// Saves what is selected in Finder and the tabs of the browser window in front under a name. The task is for a test to wait on.
    @discardableResult
    func saveCheckpoint(named name: String, note: String) -> Task<Void, Never> {
        host.leave()
        return PanelWork.perform { [weak self, finderItems = environment.finderItems, tabs = environment.tabs] in
            let files = await Task { @concurrent in await finderItems() }.value
            let items = await Checkpoint.items(files: files, tabs: tabs())
            guard let self else { return }
            guard !items.isEmpty || !note.isEmpty else {
                host.showHUD(String(localized: "Nothing to save. Select files in Finder, open a browser window, or add a note after a colon.", bundle: .floe))
                return
            }
            let checkpoint = Checkpoint(name: name, note: note, items: items, saved: Date())
            let replaces = store.all.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            store.save(checkpoint)
            reload()
            host.record(Receipt.saved(checkpoint, replacing: replaces))
            host.showHUD(String(localized: "Saved \(name): \(checkpoint.summary)", bundle: .floe, comment: "The first placeholder is a checkpoint's name, the second what it holds, such as 3 files and 5 tabs."))
        }
    }

    /// Opens what a checkpoint holds: text and code in the editor chosen in Settings, other files in their apps, folders
    /// in Finder, links in the chosen browser. What is gone is said, and listed.
    func resume(_ checkpoint: Checkpoint) {
        host.leave()
        let missing = checkpoint.missing()
        let editor = host.chosenEditor()
        for item in checkpoint.items where !missing.contains(item) {
            switch item.kind {
            case .file: open(URL(fileURLWithPath: item.value), editor: editor)
            case .link: URL(string: item.value).map(host.openLink)
            }
        }
        if missing.isEmpty {
            host.showHUD(checkpoint.note.isEmpty ? String(localized: "Resumed \(checkpoint.name)", bundle: .floe, comment: "The placeholder is a checkpoint's name.") : checkpoint.note)
        } else {
            host.showHUD(String(localized: "\(missing.count) of \(checkpoint.items.count) are missing", bundle: .floe, comment: "Both placeholders are numbers: how many of a checkpoint's files are gone, and how many things it holds."))
            host.showOutput(checkpoint.name, checkpoint.details())
        }
    }

    private func open(_ file: URL, editor: ResolvedApp?) {
        if let handoff = Checkpoint.editorHandoff(for: file, editor: editor) {
            environment.openIn(handoff)
        } else {
            environment.openFile(file)
        }
    }

    /// Deletes the checkpoint a receipt names from the list, never the files it lists. False when it is no longer there.
    func deleteCheckpoint(_ identifier: String) -> Bool {
        guard let id = UUID(uuidString: identifier), store.all.contains(where: { $0.id == id }) else { return false }
        store.delete(id)
        reload()
        return true
    }

    func checkpointActions(_ checkpoint: Checkpoint) -> [ItemAction?] {
        [
            ItemAction(title: String(localized: "Show Details", bundle: .floe), symbol: "doc.text") { [weak self] in
                self?.host.hidePanel()
                self?.host.showOutput(checkpoint.name, checkpoint.details())
            },
            ItemAction(title: String(localized: "Save Again", bundle: .floe, comment: "An action that saves a checkpoint over itself with what is open now."), symbol: "arrow.triangle.2.circlepath") { [weak self] in
                self?.saveCheckpoint(named: checkpoint.name, note: checkpoint.note)
            },
            ItemAction(title: String(localized: "Copy Note", bundle: .floe), symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(checkpoint.note)
                self?.host.showHUD(String(localized: "Copied the note", bundle: .floe))
            },
            nil,
            ItemAction(title: String(localized: "Delete Checkpoint…", bundle: .floe), symbol: "trash") { [weak self] in
                guard let self else { return }
                host.hidePanel()
                guard environment.confirmsDelete(checkpoint) else { return }
                store.delete(checkpoint.id)
                reload()
            },
        ]
    }
}

extension CheckpointRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        switch item {
        case .checkpoint: String(localized: "Resume", bundle: .floe, comment: "A verb on a button: open what a checkpoint holds.")
        case .checkpointDraft: String(localized: "Save", bundle: .floe)
        default: nil
        }
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case let .checkpoint(checkpoint): resume(checkpoint)
        case let .checkpointDraft(name, note): saveCheckpoint(named: name, note: note)
        default: return false
        }
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .checkpoint(checkpoint) = item else { return nil }
        return checkpointActions(checkpoint)
    }
}
