//
//  CheckpointRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What saving a checkpoint does with the apps that are open.
enum CheckpointApps {
    case ignored
    /// Saved in the list, and left open.
    case listed
    case hidden
    case quit
}

/// What saving and resuming a checkpoint reach outside the launcher through. Tests replace its parts.
struct CheckpointEnvironment {
    /// What is selected in Finder, or the folder in front. Empty when Finder may not be asked.
    var finderItems: @Sendable () async -> [URL] = { await (try? FinderSelection.selectionOrFolder()) ?? [] }
    /// The tabs open in the browsers Floe can ask.
    var tabs: @Sendable () async -> [BrowserTab] = {
        await BrowserTabs.read(BrowserApp.all.filter(BrowserApp.isRunning), run: AppleScript.run).tabs
    }

    var openApps: () -> [Checkpoint.Item] = { SessionApps.items() }
    var hideApps: ([Checkpoint.Item]) -> Void = { SessionApps.hide($0) }
    var quitApps: ([Checkpoint.Item]) -> Void = { SessionApps.quit($0) }
    var isStoppedBrowser: (URL) -> Bool = { SessionApps.isStoppedBrowser($0) }
    /// The wait between two reads of a starting browser's tabs.
    var pause: @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(1)) }
    /// Shows an app that is running or opens one that is not, and says whether it comes to the front.
    var bringBack: (URL, _ activates: Bool) -> Void = { SessionApps.bringBack($0, activates: $1) }
    /// Opens a file in its own app, or a folder in Finder.
    var openFile: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Opens files in the app a role stands for.
    var openIn: (Handoff) -> Void = { PreferredApps.open($0) }
    var confirmsDelete: (Checkpoint, _ then: @escaping () -> Void) -> Void = { checkpoint, goAhead in
        Confirm.destructiveInPanel(
            String(localized: "Delete the checkpoint “\(checkpoint.name)”?", bundle: .floe, comment: "The placeholder is the name the user gave a checkpoint."),
            detail: String(localized: "Its files and tabs are not touched. Only the list of them goes.", bundle: .floe),
            button: String(localized: "Delete", bundle: .floe),
            then: goAhead
        )
    }
}

/// Checkpoints, as the launcher saves and resumes them.
final class CheckpointRows {
    /// What checkpoints ask of the launcher.
    struct Host {
        var hidePanel: () -> Void = { /* set by LauncherFeatures */ }
        var showHUD: (String) -> Void = { _ in
            // Set by LauncherFeatures.
        }
        /// Hides the panel and goes back to the root search.
        var leave: () -> Void = { /* set by LauncherFeatures */ }
        var record: (Receipt) -> Void = { _ in
            // Set by LauncherFeatures.
        }
        /// Shows text in the output window.
        var showOutput: (_ title: String, _ text: String) -> Void = { _, _ in
            // Set by LauncherFeatures.
        }
        /// Opens a link in the browser the role says.
        var openLink: (URL) -> Void = { _ in
            // Set by LauncherFeatures.
        }
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

    /// Saves what is selected in Finder and the tabs of the browser window in front under a name, with the open apps if
    /// asked. Apps are put away only once the rest is read and saved. The task is for a test to wait on.
    @discardableResult
    func saveCheckpoint(named name: String, note: String, apps: CheckpointApps = .ignored) -> Task<Void, Never> {
        host.leave()
        let openApps = apps == .ignored ? [] : environment.openApps()
        return Task { [weak self, finderItems = environment.finderItems, tabs = environment.tabs] in
            let files = await Task { @concurrent in await finderItems() }.value
            let items = await Checkpoint.items(files: files, tabs: tabs(), apps: openApps)
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
            // An app is put away only once the list that brings it back is on disk.
            guard store.all.contains(where: { $0.id == checkpoint.id }) else { return }
            switch apps {
            case .ignored, .listed: break
            case .hidden: environment.hideApps(openApps)
            case .quit: environment.quitApps(openApps)
            }
        }
    }

    /// Opens what a checkpoint holds: apps first, so the rest lands in front of them, then text and code in the chosen
    /// editor, other files in their apps, folders in Finder, links in the chosen browser. What is gone is said, and listed.
    /// A test waits on the task, which exists only when a checkpoint holds apps and links.
    @discardableResult
    func resume(_ checkpoint: Checkpoint) -> Task<Void, Never>? {
        host.leave()
        let missing = checkpoint.missing()
        let editor = host.chosenEditor()
        let present = checkpoint.items.filter { !missing.contains($0) }
        let apps = present.filter { $0.kind == .app }
        let browserStarts = apps.contains { environment.isStoppedBrowser(URL(fileURLWithPath: $0.value)) }
        for app in apps {
            environment.bringBack(URL(fileURLWithPath: app.value), app == apps.last)
        }
        for file in present where file.kind == .file {
            open(URL(fileURLWithPath: file.value), editor: editor)
        }
        let links = present.filter { $0.kind == .link }
        let opening = open(links, skippingOpenTabs: checkpoint.holdsApps, browserStarts: browserStarts)
        if missing.isEmpty {
            host.showHUD(checkpoint.note.isEmpty ? String(localized: "Resumed \(checkpoint.name)", bundle: .floe, comment: "The placeholder is a checkpoint's name.") : checkpoint.note)
        } else {
            host.showHUD(String(localized: "\(missing.count) of \(checkpoint.items.count) are missing", bundle: .floe, comment: "Both placeholders are numbers: how many of a checkpoint's files are gone, and how many things it holds."))
            host.showOutput(checkpoint.name, checkpoint.details())
        }
        return opening
    }

    /// Opens links in the chosen browser. A browser that was hidden still has its tabs and one that starts may restore
    /// them, so those are not opened twice.
    private func open(_ links: [Checkpoint.Item], skippingOpenTabs: Bool, browserStarts: Bool) -> Task<Void, Never>? {
        guard skippingOpenTabs, !links.isEmpty else {
            links.compactMap { URL(string: $0.value) }.forEach(host.openLink)
            return nil
        }
        return Task { [weak self, tabs = environment.tabs, pause = environment.pause] in
            let found = await Task { @concurrent in
                browserStarts ? await Checkpoint.settledTabs(read: tabs, pause: pause) : await tabs()
            }.value
            let open = Set(found.map(\.url))
            guard let self else { return }
            links.filter { !open.contains($0.value) }.compactMap { URL(string: $0.value) }.forEach(host.openLink)
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
                self?.saveCheckpoint(named: checkpoint.name, note: checkpoint.note, apps: checkpoint.holdsApps ? .listed : .ignored)
            },
            ItemAction(title: String(localized: "Copy Note", bundle: .floe), symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(checkpoint.note)
                self?.host.showHUD(String(localized: "Copied the note", bundle: .floe))
            },
            nil,
            ItemAction(title: String(localized: "Delete Checkpoint…", bundle: .floe), symbol: "trash") { [weak self] in
                guard let self else { return }
                environment.confirmsDelete(checkpoint) { [weak self] in
                    // The rows on show were found before the delete, so the panel goes rather than show it still.
                    self?.host.hidePanel()
                    self?.store.delete(checkpoint.id)
                    self?.reload()
                }
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
        switch item {
        case let .checkpoint(checkpoint): checkpointActions(checkpoint)
        case let .checkpointDraft(name, note): draftActions(name: name, note: note)
        default: nil
        }
    }

    /// Return saves files and tabs alone. Hiding or quitting the apps is chosen here.
    private func draftActions(name: String, note: String) -> [ItemAction?] {
        [
            ItemAction(title: String(localized: "Save and Hide Apps", bundle: .floe, comment: "An action that saves a checkpoint with the open apps, then hides them."), symbol: "eye.slash") { [weak self] in
                self?.saveCheckpoint(named: name, note: note, apps: .hidden)
            },
            ItemAction(title: String(localized: "Save and Quit Apps", bundle: .floe, comment: "An action that saves a checkpoint with the open apps, then asks them to quit."), symbol: "xmark.square") { [weak self] in
                self?.saveCheckpoint(named: name, note: note, apps: .quit)
            },
        ]
    }
}
