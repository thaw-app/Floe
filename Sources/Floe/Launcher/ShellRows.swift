//
//  ShellRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What the shell rows reach outside the launcher through: the shell, a terminal, the output window, the clipboard,
/// the process table, Finder.
/// One value, so a test stands in for all of it in one place.
struct ShellEnvironment {
    /// Runs a command in a folder, or the home folder, and answers with the line for the HUD and everything printed.
    var run: @Sendable (String, URL?) async -> (line: String, output: String) = { await ShellCommand.finished($0, in: $1) }
    var showOutput: (_ title: String, _ output: String) -> Void = { ScriptOutputWindow.show(title: $0, output: $1) }
    /// Ends a process, and answers whether the system took the request.
    var endProcess: (RunningProcess, _ force: Bool) -> Bool = { Processes.end($0, force: $1) }
    /// Asks before a process is ended where it stands.
    var confirmsForceQuit: (RunningProcess) -> Bool = { process in
        Confirm.destructive(
            String(localized: "Force “\(process.name)” to quit?", bundle: .floe, comment: "The placeholder is an app's name."),
            detail: String(localized: "You will lose any changes you haven't saved.", bundle: .floe),
            button: String(localized: "Force Quit", bundle: .floe, comment: "An action that ends a process at once.")
        )
    }

    var hasProgram: (String) -> Bool = { ShellCommand.isProgram($0) }
    /// The folder of the Finder window in front.
    var finderFolder: () async throws -> URL = { try await FinderSelection.folder() }
    var askForAutomation: (_ app: String) -> Void = { SystemCommand.askForAutomation(toControl: $0) }
    var runInTerminal: (String, ResolvedApp?) throws -> Void = { try ShellCommand.runInTerminal($0, terminal: $1) }
    var copy: (String) -> Void = { NSPasteboard.general.copy($0) }
    var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Asks what to call a command that is being saved, and answers nil when the user cancels.
    var nameForSaving: (_ command: String) -> String? = { ShellEnvironment.askName(for: $0) }
    /// Keeps a command as a script command with the given title.
    var save: (_ command: String, _ title: String) throws -> Void = { _ = try ShellCommand.save($0, as: $1) }

    private static func askName(for command: String) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save this command", bundle: .floe)
        alert.informativeText = command
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = String(localized: "Name", bundle: .floe, comment: "A text field's placeholder: the name to give a saved command.")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: String(localized: "Save", bundle: .floe))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .floe))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

/// Shell commands, their suggestions and running processes, as the launcher acts on them.
final class ShellRows {
    /// What the shell asks of the launcher.
    struct Host {
        var hidePanel: () -> Void = { /* set by LauncherFeatures */ }
        var showHUD: (String) -> Void = { _ in
            // Set by LauncherFeatures.
        }
        /// Keeps the search for later, hides the panel and goes back to the root search.
        var leave: () -> Void = { /* set by LauncherFeatures */ }
        var record: (Receipt) -> Void = { _ in
            // Set by LauncherFeatures.
        }
        /// Puts text in the search field, to run or to go on typing from.
        var setQuery: (String) -> Void = { _ in
            // Set by LauncherFeatures.
        }
        /// Reads the rows again: a process that was ended is gone.
        var refresh: () -> Void = { /* set by LauncherFeatures */ }
        /// A command was saved as a script command.
        var scriptsChanged: () -> Void = { /* set by LauncherFeatures */ }
    }

    var environment = ShellEnvironment()
    var host = Host()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Return on a row of the shell.
    func perform(_ action: ShellAction) {
        switch action {
        case let .run(command, terminal): runShellCommand(command, terminal: terminal)
        case let .complete(row): complete(with: row)
        case let .quit(process): end(process, force: false)
        }
    }

    /// Runs a typed command: out of sight, with its first line of output in the HUD, or in a terminal
    /// when the user asks for one or the command needs one.
    func runShellCommand(_ command: String, terminal: ResolvedApp?, inTerminal: Bool = false, showingOutput: Bool = false, in folder: URL? = nil) {
        host.leave()
        guard inTerminal || ShellCommand.needsATerminal(command) else {
            // A manual is for reading: it goes to the window whichever key ran it.
            let reading = ShellCommand.asReading(command)
            PanelWork.perform { [weak self, run = environment.run] in
                let finished = await run(reading ?? command, folder)
                // A manual that was read changed nothing: no receipt.
                if reading == nil {
                    self?.host.record(Receipt(date: Date(), kind: .command, subject: command, detail: finished.line))
                }
                if showingOutput || reading != nil {
                    self?.environment.showOutput(command, finished.output)
                } else {
                    self?.host.showHUD(finished.line)
                }
            }
            return
        }
        do {
            try environment.runInTerminal(command, terminal)
            host.record(Receipt(date: Date(), kind: .command, subject: command, detail: String(localized: "Handed to the terminal", bundle: .floe)))
        } catch {
            host.showHUD(error.localizedDescription)
        }
    }

    /// Return with a key held: Command for a terminal, Option for the whole output in a window, Shift for Finder's folder.
    func runShellCommand(_ command: String, terminal: ResolvedApp?, with flags: NSEvent.ModifierFlags) {
        switch flags {
        case .shift: runInFinderFolder(command, terminal: terminal)
        case .command: runShellCommand(command, terminal: terminal, inTerminal: true)
        case .option: runShellCommand(command, terminal: terminal, showingOutput: true)
        default: runShellCommand(command, terminal: terminal)
        }
    }

    /// Runs a command in the folder of the Finder window in front, and shows what it printed.
    func runInFinderFolder(_ command: String, terminal: ResolvedApp?) {
        PanelWork.perform { [self] in
            do {
                let folder = try await environment.finderFolder()
                runShellCommand(command, terminal: terminal, showingOutput: true, in: folder)
            } catch SelectionError.automationRefused {
                environment.askForAutomation("Finder")
            } catch {
                host.showHUD(error.localizedDescription)
            }
        }
    }

    /// Runs a command out of sight and puts everything it printed on the clipboard.
    func copyOutput(of command: String) {
        host.leave()
        PanelWork.perform { [weak self, run = environment.run] in
            let finished = await run(command, nil)
            self?.host.record(Receipt(date: Date(), kind: .command, subject: command, detail: finished.line))
            self?.environment.copy(finished.output)
            self?.host.showHUD(String(localized: "Copied the output", bundle: .floe))
        }
    }

    /// Asks for a name and keeps the command as a script command, which the search then finds by that name.
    func saveShellCommand(_ command: String) {
        host.hidePanel()
        let title = environment.nameForSaving(command)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return }
        do {
            try environment.save(command, title)
            host.scriptsChanged()
            host.showHUD(String(localized: "Saved \(title)", bundle: .floe, comment: "Shown briefly after saving. The placeholder is the name the user gave."))
        } catch {
            host.showHUD(error.localizedDescription)
        }
    }

    /// Puts a row's text into the search after the prefix, to run or to go on typing from. Tab does this on any
    /// suggestion, and Return on one that is not yet a whole command.
    func complete(with row: ShellRow) {
        host.setQuery(settings.shell.prefix.rawValue + " " + row.text)
    }

    /// Ends a process and says so. The panel stays, with the list read again, for the next one.
    func end(_ process: RunningProcess, force: Bool) {
        if environment.endProcess(process, force) {
            host.record(Receipt(date: Date(), kind: .process, subject: process.name, detail: Processes.label(for: process)))
            host.showHUD(force
                ? String(localized: "Forced \(process.name) to quit", bundle: .floe, comment: "The placeholder is an app's name.")
                : String(localized: "Quitting \(process.name)", bundle: .floe, comment: "The placeholder is an app's name."))
        } else {
            host.showHUD(String(localized: "Couldn't quit \(process.name)", bundle: .floe, comment: "The placeholder is a program's name."))
        }
        Processes.forget()
        host.refresh()
    }

    /// The Actions menu of a row of the shell, after what Return does. Empty for any other row.
    func shellActions(for item: RootItem) -> [ItemAction?] {
        switch item.shellAction {
        case let .run(command, terminal): commandActions(command, terminal: terminal)
        case let .quit(process): processActions(process)
        case .complete, nil: []
        }
    }

    private func commandActions(_ command: String, terminal: ResolvedApp?) -> [ItemAction?] {
        readingActions(for: command, terminal: terminal) + [
            ItemAction(title: String(localized: "Run and Show Output", bundle: .floe), symbol: "text.alignleft") { [weak self] in
                self?.runShellCommand(command, terminal: terminal, showingOutput: true)
            },
            ItemAction(title: String(localized: "Run and Copy Output", bundle: .floe), symbol: "doc.on.clipboard") { [weak self] in
                self?.copyOutput(of: command)
            },
            ItemAction(title: String(localized: "Run in Finder\u{2019}s Folder", bundle: .floe), symbol: "folder") { [weak self] in
                self?.runInFinderFolder(command, terminal: terminal)
            },
            ItemAction(title: String(localized: "Run in Terminal", bundle: .floe), symbol: "terminal") { [weak self] in
                self?.runShellCommand(command, terminal: terminal, inTerminal: true)
            },
            ItemAction(title: String(localized: "Save as Script Command…", bundle: .floe), symbol: "square.and.arrow.down") { [weak self] in
                self?.saveShellCommand(command)
            },
            nil,
            ItemAction(title: String(localized: "Copy Command", bundle: .floe), symbol: "doc.on.doc") { [weak self] in
                self?.environment.copy(command)
                self?.host.showHUD(String(localized: "Copied \(command)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            },
        ]
    }

    /// The manual of the command's program, and its examples on a Mac that has `tldr`.
    private func readingActions(for command: String, terminal: ResolvedApp?) -> [ItemAction?] {
        guard let program = ShellCommand.program(of: command) else { return [] }
        var actions: [ItemAction?] = [
            ItemAction(title: String(localized: "Show Manual for \(program)", bundle: .floe, comment: "The placeholder is the name of a command-line program."), symbol: "book") { [weak self] in
                self?.runShellCommand("man \(program)", terminal: terminal)
            },
        ]
        if environment.hasProgram("tldr") {
            actions.append(ItemAction(title: String(localized: "Show Examples for \(program)", bundle: .floe, comment: "The placeholder is the name of a command-line program."), symbol: "list.bullet.rectangle") { [weak self] in
                self?.runShellCommand(ShellCommand.examples(for: program), terminal: terminal, showingOutput: true)
            })
        }
        return actions
    }

    private func processActions(_ process: RunningProcess) -> [ItemAction?] {
        [
            ItemAction(title: String(localized: "Force Quit…", bundle: .floe), symbol: "xmark.octagon") { [weak self] in
                guard let self, environment.confirmsForceQuit(process) else { return }
                end(process, force: true)
            },
            nil,
            ItemAction(title: String(localized: "Show in Finder", bundle: .floe), symbol: "folder") { [weak self] in
                self?.environment.reveal(URL(fileURLWithPath: process.path))
                self?.host.hidePanel()
            },
            ItemAction(title: String(localized: "Copy Process ID", bundle: .floe), symbol: "number") { [weak self] in
                self?.environment.copy(String(process.pid))
                self?.host.showHUD(String(localized: "Copied \(String(process.pid))", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            },
        ]
    }
}

extension ShellRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        item.shellAction?.title
    }

    /// With Command a command opens in a terminal, with Option its output in a window, with Shift it runs in Finder's folder.
    func open(_ item: RootItem, flags: NSEvent.ModifierFlags) -> Bool {
        guard let action = item.shellAction else { return false }
        if case let .run(command, terminal) = action, !flags.isEmpty {
            runShellCommand(command, terminal: terminal, with: flags)
        } else {
            perform(action)
        }
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        item.shellAction == nil ? nil : shellActions(for: item)
    }

    /// Tab completes a suggestion into the search.
    func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, on item: RootItem) -> Bool {
        guard keyCode == 48, flags.isEmpty, case let .shell(row, _) = item, row.origin != .typed else { return false }
        complete(with: row)
        return true
    }
}
