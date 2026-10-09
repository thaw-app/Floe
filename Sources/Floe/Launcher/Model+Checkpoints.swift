//
//  Model+Checkpoints.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What saving and resuming a checkpoint reach outside the launcher through. Tests replace its parts.
struct CheckpointEnvironment {
    /// What is selected in Finder, or the folder in front. Empty when Finder may not be asked.
    var finderItems: @Sendable () -> [URL] = { (try? FinderSelection.selectionOrFolder()) ?? [] }
    /// The tabs open in the browsers Floe can ask, read off the main thread.
    var tabs: @Sendable () async -> [BrowserTab] = {
        await Task.detached { BrowserTabs.read(BrowserApp.all.filter(BrowserApp.isRunning), run: AppleScript.run).tabs }.value
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
extension LauncherModel {
    func reloadCheckpoints() {
        checkpoints = checkpointStore.all
    }

    /// Saves what is selected in Finder and the tabs of the browser window in front under a name. The task is for a test to wait on.
    @discardableResult
    func saveCheckpoint(named name: String, note: String) -> Task<Void, Never> {
        hidePanel()
        reset()
        return Task { [weak self, finderItems = checkpointing.finderItems, tabs = checkpointing.tabs] in
            let files = await Task { @concurrent in finderItems() }.value
            let items = await Checkpoint.items(files: files, tabs: tabs())
            guard let self else { return }
            guard !items.isEmpty || !note.isEmpty else {
                showHUD(String(localized: "Nothing to save. Select files in Finder, open a browser window, or add a note after a colon.", bundle: .floe))
                return
            }
            let checkpoint = Checkpoint(name: name, note: note, items: items, saved: Date())
            let replaces = checkpointStore.all.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            checkpointStore.save(checkpoint)
            reloadCheckpoints()
            record(Receipt.saved(checkpoint, replacing: replaces))
            showHUD(String(localized: "Saved \(name): \(checkpoint.summary)", bundle: .floe, comment: "The first placeholder is a checkpoint's name, the second what it holds, such as 3 files and 5 tabs."))
        }
    }

    /// Opens what a checkpoint holds: text and code in the editor chosen in Settings, other files in their apps, folders
    /// in Finder, links in the chosen browser. What is gone is said, and listed.
    func resume(_ checkpoint: Checkpoint) {
        hidePanel()
        reset()
        let missing = checkpoint.missing()
        // Only an editor the user chose: the role's stand-in is the app text files open in anyway.
        let editor = PreferredApps.chosenApp(settings.appChoice(for: .editor), installed: appLookup)
        for item in checkpoint.items where !missing.contains(item) {
            switch item.kind {
            case .file: open(URL(fileURLWithPath: item.value), editor: editor)
            case .link: URL(string: item.value).map(openLink)
            }
        }
        if missing.isEmpty {
            showHUD(checkpoint.note.isEmpty ? String(localized: "Resumed \(checkpoint.name)", bundle: .floe, comment: "The placeholder is a checkpoint's name.") : checkpoint.note)
        } else {
            showHUD(String(localized: "\(missing.count) of \(checkpoint.items.count) are missing", bundle: .floe, comment: "Both placeholders are numbers: how many of a checkpoint's files are gone, and how many things it holds."))
            shell.showOutput(checkpoint.name, checkpoint.details())
        }
    }

    private func open(_ file: URL, editor: ResolvedApp?) {
        if let handoff = Checkpoint.editorHandoff(for: file, editor: editor) {
            checkpointing.openIn(handoff)
        } else {
            checkpointing.openFile(file)
        }
    }

    /// Deletes the checkpoint a receipt names from the list, never the files it lists. False when it is no longer there.
    func deleteCheckpoint(_ identifier: String) -> Bool {
        guard let id = UUID(uuidString: identifier), checkpointStore.all.contains(where: { $0.id == id }) else { return false }
        checkpointStore.delete(id)
        reloadCheckpoints()
        return true
    }

    func checkpointActions(_ checkpoint: Checkpoint) -> [ItemAction?] {
        [
            ItemAction(title: String(localized: "Show Details", bundle: .floe), symbol: "doc.text") { [weak self] in
                self?.hidePanel()
                self?.shell.showOutput(checkpoint.name, checkpoint.details())
            },
            ItemAction(title: String(localized: "Save Again", bundle: .floe, comment: "An action that saves a checkpoint over itself with what is open now."), symbol: "arrow.triangle.2.circlepath") { [weak self] in
                self?.saveCheckpoint(named: checkpoint.name, note: checkpoint.note)
            },
            ItemAction(title: String(localized: "Copy Note", bundle: .floe), symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(checkpoint.note)
                self?.showHUD(String(localized: "Copied the note", bundle: .floe))
            },
            nil,
            ItemAction(title: String(localized: "Delete Checkpoint…", bundle: .floe), symbol: "trash") { [weak self] in
                guard let self else { return }
                hidePanel()
                guard checkpointing.confirmsDelete(checkpoint) else { return }
                checkpointStore.delete(checkpoint.id)
                reloadCheckpoints()
            },
        ]
    }
}
