//
//  ExtensionRunner.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices

/// The extension command the panel runs: starting it, what it asks the app to do, running it again and ending it.
/// It is handed what it needs from the panel as a Host, and knows nothing of the launcher.
final class ExtensionRunner: ObservableObject {
    /// What the panel does for a command.
    struct Host {
        var showPanel: () -> Void = { /* set by the launcher's model */ }
        var hidePanel: () -> Void = { /* set by the launcher's model */ }
        var showHUD: (String) -> Void = { _ in
            // Set by the launcher's model.
        }
        /// The search field takes the keys again: the command's view is gone.
        var refocus: () -> Void = { /* set by the launcher's model */ }
        /// Whether the panel is on screen, so a toast is drawn in the command's footer rather than said as a HUD.
        var isPanelShown: () -> Bool = { false }
        /// Whether the panel is hidden with the command kept for the user to come back to.
        var isWaitingToResume: () -> Bool = { false }
        /// Asks for what a command needs before it can run: its required preferences, or its arguments.
        var beginSetup: (SetupRequest) -> Void = { _ in
            // Set by the launcher's model.
        }
        /// Running a menu-bar command is choosing whether it has a status item.
        var toggleMenuBar: (ExtensionCommand) -> Void = { _ in
            // Set by the launcher's model.
        }
        /// Opens a link or a file, in a named app when there is one.
        var open: (_ target: String, _ application: String?) -> Void = { _, _ in
            // Set by the launcher's model.
        }
        /// Opens the command's settings, or asks for the one preference a sign-in needs.
        var showPreferences: ([String: Any], ExtensionSession) -> Void = { _, _ in
            // Set by the launcher's model.
        }
        /// The extension's manifest changed on disk.
        var manifestChanged: () -> Void = { /* set by the launcher's model */ }
        /// Floe's clipboard history, newest first, which the command reads older copies from.
        var clipboardHistory: @MainActor @Sendable () -> [ClipboardEntry] = { [] }
    }

    @Published private(set) var session: ExtensionSession?
    var host = Host()
    /// Where copies go; tests pass a pasteboard of their own.
    var pasteboard = NSPasteboard.general

    /// The last toast said as a HUD, so the same one is not said twice.
    private var toastLine: (session: ObjectIdentifier, id: Int, line: String)?
    /// Watches the open command's extension while it is one being developed (see HotReload.swift).
    private var sourceWatcher: DirectoryWatcher?

    /// A command that first has to ask for preferences or arguments starts without `launchCommand`'s context.
    func run(_ command: ExtensionCommand, arguments: [String: Any]? = nil, context: [String: Any]? = nil) {
        let missing = PreferenceStore.missingRequired(for: command)
        if command.mode == "menu-bar", missing.isEmpty {
            host.toggleMenuBar(command)
            return
        }
        if let session {
            end(session)
        }
        if !missing.isEmpty {
            // The arguments wait in the form: once the preferences are saved, the command runs with them.
            host.beginSetup(SetupRequest(command: command, kind: .preferences, fields: command.preferences, arguments: arguments))
        } else if arguments == nil, !command.arguments.isEmpty {
            host.beginSetup(SetupRequest(command: command, kind: .arguments, fields: command.arguments))
        } else {
            if command.mode == "view" {
                host.showPanel()
            }
            launch(command, arguments: arguments ?? [:], context: context)
        }
    }

    /// Runs the open command again, with the same arguments.
    func retry() {
        guard let session else { return }
        let command = session.command
        let arguments = session.arguments
        let context = session.launchContext
        end(session)
        run(command, arguments: arguments, context: context)
    }

    func copyFailure() {
        guard let session, let failure = session.failure else { return }
        PasteboardContent.write(text: "\(session.command.extensionTitle) › \(session.command.title)\n\(failure.message)\n\n\(failure.details)", html: nil, file: nil, to: pasteboard)
        host.showHUD(String(localized: "Copied error details", bundle: .floe))
    }

    func end(_ session: ExtensionSession) {
        // Trailing messages (a HUD after closeMainWindow, say) still need to be read.
        session.stop(after: 0.5)
        if self.session === session {
            self.session = nil
            sourceWatcher = nil
            host.refocus()
        }
    }

    /// Ends the open command, if there is one.
    func endOpenCommand() {
        if let session {
            end(session)
        }
    }

    private func launch(_ command: ExtensionCommand, arguments: [String: Any], context: [String: Any]? = nil) {
        Log.extensions.info("Running \(command.extensionName)/\(command.name) (\(command.mode))")
        let session = ExtensionSession(command: command, arguments: arguments, launchContext: context)
        session.onMessage = { [weak self, weak session] message in
            guard let self, let session else { return }
            handle(message, from: session)
        }
        session.answer = Self.answer(withHistory: host.clipboardHistory)
        self.session = session
        session.start()
        sourceWatcher = HotReload.watcher(for: command) { [weak self, weak session] paths in
            guard let self, let session else { return }
            reload(session, changed: paths)
        }
    }

    /// A file of the open command's extension was saved: runs the command again as retry does.
    /// A panel that is hidden while its command waits to be resumed stays hidden.
    private func reload(_ watched: ExtensionSession, changed paths: [String]) {
        guard session === watched else { return }
        if HotReload.changesManifest(paths) {
            host.manifestChanged()
        }
        if host.isWaitingToResume() {
            end(watched)
            launch(watched.command, arguments: watched.arguments, context: watched.launchContext)
        } else {
            retry()
        }
    }

    /// The app's answers, with `Clipboard.read`'s older copies taken from Floe's history.
    static func answer(withHistory history: @escaping @MainActor @Sendable () -> [ClipboardEntry])
        -> @concurrent @Sendable (HostRequest, @Sendable (String) async -> Void) async throws -> Any {
        { request, emit in
            guard case let .clipboardRead(offset) = request, offset > 0 else {
                return try await HostRequest.answer(request, emit: emit)
            }
            return await MainActor.run { PasteboardContent.copy(offset: offset, in: history(), directory: ClipboardHistoryStore.directory) }
        }
    }

    // MARK: What a command asks for

    func handle(_ message: [String: Any], from session: ExtensionSession) {
        switch message["type"] as? String {
        case "exit", "popToRoot":
            // A command launched in the background by another leaves the panel to the one on screen.
            let wasBackground = session.command.mode != "view" && self.session === session
            end(session)
            if wasBackground {
                host.hidePanel()
            }
        case "crashed" where session.command.mode != "view":
            end(session)
            host.showHUD(String(localized: "\(session.command.title) failed", bundle: .floe, comment: "The placeholder is the name of a command."))
        case "close":
            host.hidePanel()
        case "hud":
            host.showHUD(message["title"] as? String ?? "")
            host.hidePanel()
        case "copy":
            copy(message)
        case "paste":
            copy(message, concealed: false)
            pasteCopied()
        case "open":
            host.open(message["target"] as? String ?? "", message["application"] as? String)
        case "openPreferences", "signIn":
            host.showPreferences(message, session)
        default:
            showToastWithoutFooter(message, of: session)
        }
    }

    /// Handles open, copy, paste and hud from sessions the panel doesn't own (menu-bar extras,
    /// background runs). Background runs never open the panel.
    func handleBackgroundMessage(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "hud":
            host.showHUD(message["title"] as? String ?? "")
        case "copy":
            copy(message)
        case "paste":
            // A background run never takes the keyboard from the user; it only copies.
            copy(message, concealed: false)
            host.showHUD(String(localized: "Copied. Press ⌘V to paste.", bundle: .floe))
        case "open":
            host.open(message["target"] as? String ?? "", message["application"] as? String)
        default:
            break
        }
    }

    func paste(text: String) {
        PasteboardContent.write(text: text, html: nil, file: nil, to: pasteboard)
        pasteCopied()
    }

    /// Presses Command-V in the app behind the panel, or says how to when Accessibility is not granted.
    private func pasteCopied() {
        if AXIsProcessTrusted() {
            host.hidePanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                KeySimulation.paste()
            }
        } else {
            host.showHUD(String(localized: "Copied. Press ⌘V to paste.", bundle: .floe))
            host.hidePanel()
        }
    }

    /// Writes what a copy or paste message carries. A paste is never concealed: it was meant to be seen.
    private func copy(_ message: [String: Any], concealed: Bool? = nil) {
        PasteboardContent.write(
            text: message["text"] as? String ?? "",
            html: message["html"] as? String,
            file: message["file"] as? String,
            concealed: concealed ?? (message["concealed"] as? Bool ?? false),
            to: pasteboard
        )
    }

    /// A toast is drawn in the footer of its command's view. A command without a view has no footer, and a
    /// hidden panel shows none, so there the toast becomes a HUD, as it does in Raycast.
    private func showToastWithoutFooter(_ message: [String: Any], of session: ExtensionSession) {
        guard message["type"] as? String == "toast", let toast = session.toast, !toast.line.isEmpty else { return }
        if session.command.mode == "view" {
            // A view that is only hidden keeps its progress to itself; what it finished or failed at is said.
            guard !host.isPanelShown(), toast.style != "animated" else { return }
        }
        // Setting a toast's title and then its message sends it twice.
        let shown = (ObjectIdentifier(session), toast.id, toast.line)
        guard toastLine.map({ $0 == shown }) != true else { return }
        toastLine = shown
        host.showHUD(toast.line)
    }
}
