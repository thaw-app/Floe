//
//  Model+Shell.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What the shell rows reach outside the launcher through: the shell, the output window, the process table, Finder.
/// One value on the model, so a test stands in for all of it in one place.
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
    var finderFolder: () throws -> URL = { try FinderSelection.folder() }
}

/// Shell commands, their suggestions and running processes, as the launcher acts on them.
extension LauncherModel {
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
        // Before the panel goes back to the root, which empties the search.
        rememberQuery()
        hidePanel()
        reset()
        guard inTerminal || ShellCommand.needsATerminal(command) else {
            // A manual is for reading: it goes to the window whichever key ran it.
            let reading = ShellCommand.asReading(command)
            Task { [weak self, run = shell.run] in
                let finished = await run(reading ?? command, folder)
                if showingOutput || reading != nil {
                    self?.shell.showOutput(command, finished.output)
                } else {
                    self?.showHUD(finished.line)
                }
            }
            return
        }
        do {
            try ShellCommand.runInTerminal(command, terminal: terminal)
        } catch {
            showHUD(error.localizedDescription)
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
        do {
            let folder = try shell.finderFolder()
            runShellCommand(command, terminal: terminal, showingOutput: true, in: folder)
        } catch SelectionError.automationRefused {
            SystemCommand.askForAutomation(toControl: "Finder")
        } catch {
            showHUD(error.localizedDescription)
        }
    }

    /// Runs a command out of sight and puts everything it printed on the clipboard.
    func copyOutput(of command: String) {
        rememberQuery()
        hidePanel()
        reset()
        Task { [weak self, run = shell.run] in
            let finished = await run(command, nil)
            NSPasteboard.general.copy(finished.output)
            self?.showHUD(String(localized: "Copied the output", bundle: .floe))
        }
    }

    /// Asks for a name and keeps the command as a script command, which the search then finds by that name.
    func saveShellCommand(_ command: String) {
        hidePanel()
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
        let title = alert.runModal() == .alertFirstButtonReturn ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard !title.isEmpty else { return }
        do {
            _ = try ShellCommand.save(command, as: title)
            reloadScripts()
            showHUD(String(localized: "Saved \(title)", bundle: .floe, comment: "Shown briefly after saving. The placeholder is the name the user gave."))
        } catch {
            showHUD(error.localizedDescription)
        }
    }

    /// Puts a row's text into the search after the prefix, to run or to go on typing from. Tab does this on any
    /// suggestion, and Return on one that is not yet a whole command.
    func complete(with row: ShellRow) {
        query = settings.shell.prefix.rawValue + " " + row.text
        focusToken += 1
    }

    /// Ends a process and says so. The panel stays, with the list read again, for the next one.
    func end(_ process: RunningProcess, force: Bool) {
        if shell.endProcess(process, force) {
            showHUD(force
                ? String(localized: "Forced \(process.name) to quit", bundle: .floe, comment: "The placeholder is an app's name.")
                : String(localized: "Quitting \(process.name)", bundle: .floe, comment: "The placeholder is an app's name."))
        } else {
            showHUD(String(localized: "Couldn't quit \(process.name)", bundle: .floe, comment: "The placeholder is a program's name."))
        }
        Processes.forget()
        refresh()
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
                NSPasteboard.general.copy(command)
                self?.showHUD(String(localized: "Copied \(command)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
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
        if shell.hasProgram("tldr") {
            actions.append(ItemAction(title: String(localized: "Show Examples for \(program)", bundle: .floe, comment: "The placeholder is the name of a command-line program."), symbol: "list.bullet.rectangle") { [weak self] in
                self?.runShellCommand(ShellCommand.examples(for: program), terminal: terminal, showingOutput: true)
            })
        }
        return actions
    }

    private func processActions(_ process: RunningProcess) -> [ItemAction?] {
        [
            ItemAction(title: String(localized: "Force Quit…", bundle: .floe), symbol: "xmark.octagon") { [weak self] in
                guard let self, shell.confirmsForceQuit(process) else { return }
                end(process, force: true)
            },
            nil,
            ItemAction(title: String(localized: "Show in Finder", bundle: .floe), symbol: "folder") { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.path)])
                self?.hidePanel()
            },
            ItemAction(title: String(localized: "Copy Process ID", bundle: .floe), symbol: "number") { [weak self] in
                NSPasteboard.general.copy(String(process.pid))
                self?.showHUD(String(localized: "Copied \(String(process.pid))", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            },
        ]
    }
}
