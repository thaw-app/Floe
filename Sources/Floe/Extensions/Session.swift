//
//  Session.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Why a command can't show its view: it threw, it crashed, or it stopped answering.
struct SessionFailure: Equatable {
    enum Kind { case error, crashed, unresponsive }
    let kind: Kind
    let message: String
    let details: String
}

struct ToastState: Equatable {
    let id: Int
    let style: String
    let title: String
    let message: String?
    var primaryTitle: String?
    var secondaryTitle: String?

    /// The toast on one line, for where there is no footer to draw it in.
    var line: String {
        [title, message ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
    }
}

/// An in-panel confirmation dialog from `confirmAlert`. The id is the host request it answers.
struct AlertState: Equatable {
    let id: Int
    let title: String
    let message: String?
    let primaryTitle: String
    let isDestructive: Bool
    let dismissTitle: String
}

/// One running extension command: a Bun process speaking NDJSON over stdin/stdout.
final class ExtensionSession: ObservableObject {
    let command: ExtensionCommand
    /// Where what the extension reaches is recorded. Tests give one of their own.
    var accessStore = ExtensionAccessStore.shared
    /// Whether the record is kept, as Settings has it now. Tests answer for themselves.
    var recordsAccess: () -> Bool = { AppSettings.shared.recordsExtensionAccess }
    let arguments: [String: Any]
    let launchType: String
    @Published private(set) var root: Node?
    /// Form field values by field id. Dates are kept as ISO 8601 strings.
    @Published var formValues: [String: Any] = [:]
    @Published var toast: ToastState?
    @Published var alert: AlertState?
    @Published var failure: SessionFailure? {
        didSet {
            if let failure {
                Log.extensions.error("\(command.extensionName)/\(command.name) failed: \(failure.message)")
            }
        }
    }

    @Published var selection = 0
    @Published var actionMenuOpen = false {
        didSet {
            actionQuery = ""
            actionPath = []
            actionSelection = 0
        }
    }

    @Published var actionSelection = 0
    /// Typed while the action menu is open; filters every action, submenus included.
    @Published var actionQuery = "" {
        didSet { actionSelection = 0 }
    }

    /// Open submenus, outermost first.
    @Published private(set) var actionPath: [Node] = []
    /// Recomputed only when the tree or the search text changes, not on every redraw.
    @Published private(set) var rows: [Row] = []
    /// Counts the times `rows` changed, so a view can tell without walking them.
    private(set) var rowsVersion = 0
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            selection = 0
            recomputeRows()
            if !suppressSearchEvent, let view, view.handlers.contains("onSearchTextChange") {
                event(view, "onSearchTextChange", [searchText])
            }
        }
    }

    /// Messages the session does not handle itself: close, exit, popToRoot, hud, open, copy, paste.
    var onMessage: ([String: Any]) -> Void = { _ in
        // Set by the model.
    }

    /// Where outgoing messages go: the host's stdin once it runs (see Session+Process.swift).
    var transport: ([String: Any]) -> Void = { _ in
        // Nothing is running yet.
    }

    /// Runs the host and ends when it does; cancelling it stops the host.
    var hostTask: Task<Void, Never>?
    /// Set while the host is running.
    var processID: pid_t?
    /// The tail of the host's stderr, shown on the error screen.
    private(set) var log = ""
    var isStopping = false
    var watchdog: Timer?
    /// Answers what the extension asks the app for; tests replace it.
    var answer: @concurrent @Sendable (HostRequest, @Sendable (String) async -> Void) async throws -> Any = HostRequest.answer
    /// Requests still being answered, by the id the host gave them (see Session+Requests.swift).
    var pendingRequests: [Int: Task<Void, Never>] = [:]
    private(set) var pingSentAt: Date?
    private var suppressSearchEvent = false

    init(command: ExtensionCommand, arguments: [String: Any] = [:], launchType: String = "userInitiated") {
        self.command = command
        self.arguments = arguments
        self.launchType = launchType
    }

    /// Set while the host is running.
    var isRunning: Bool {
        processID != nil
    }

    func send(_ message: [String: Any]) {
        transport(message)
    }

    func event(_ node: Node, _ prop: String, _ args: [Any] = []) {
        send(["type": "event", "id": node.id, "prop": prop, "args": args])
    }

    /// Applies one message the decoder has already framed, decoded and, for renders, built the tree
    /// for. Runs on the main actor, in the order the host wrote the lines.
    @MainActor
    func apply(_ message: DecodedHostMessage) {
        switch message {
        case let .render(tree):
            let previousScreen = screen?.id
            root = tree
            recomputeRows()
            if !actionPath.isEmpty {
                refreshActionPath()
            }
            if screen?.id != previousScreen {
                formValues = [:]
                suppressSearchEvent = true
                searchText = ""
                suppressSearchEvent = false
                selection = 0
                actionMenuOpen = false
            }
        case .unresolvedRender:
            // The last good tree stays on show until the whole one arrives.
            send(["type": "fullRender"])
        case let .fields(message):
            apply(message)
        }
    }

    /// Takes in a report of what the extension reached, or drops it while the record is off. Answers whether the message was one.
    private func recordedAccess(_ fields: [String: Any]) -> Bool {
        guard fields["type"] as? String == "access" else { return false }
        // A host started before the switch went off still reports.
        if recordsAccess() {
            accessStore.record(fields, for: command.extensionName)
        }
        return true
    }

    private func apply(_ fields: [String: Any]) {
        switch fields["type"] as? String {
        case "toast":
            let id = fields["id"] as? Int ?? 0
            if fields["hidden"] as? Bool == true {
                if toast?.id == id {
                    toast = nil
                }
            } else {
                let state = ToastState(
                    id: id,
                    style: fields["style"] as? String ?? "success",
                    title: fields["title"] as? String ?? "",
                    message: fields["message"] as? String,
                    primaryTitle: fields["primaryTitle"] as? String,
                    secondaryTitle: fields["secondaryTitle"] as? String
                )
                toast = state
                // The model shows it where this session has no footer on screen.
                onMessage(fields)
                // A toast with an action stays until it is dismissed or acted on.
                guard state.style != "animated", state.primaryTitle == nil, state.secondaryTitle == nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    if self?.toast == state {
                        self?.toast = nil
                    }
                }
            }
        case "error":
            let text = fields["message"] as? String ?? String(localized: "Unknown error", bundle: .floe)
            if fields["fatal"] as? Bool == true {
                let details = [fields["stack"] as? String, log.isEmpty ? nil : log].compactMap(\.self).joined(separator: "\n\n")
                failure = SessionFailure(kind: .error, message: text, details: details)
            } else {
                toast = ToastState(id: -1, style: "failure", title: String(localized: "Extension error", bundle: .floe), message: text)
                onMessage(["type": "toast"])
            }
        case "pong":
            pingSentAt = nil
            if failure?.kind == .unresponsive {
                failure = nil
            }
        case "clearSearchBar":
            searchText = ""
        default:
            // Requests are in Session+Requests.swift; the rest is the model's.
            if !recordedAccess(fields), !handleRequest(fields) {
                onMessage(fields)
            }
        }
    }

    func appendLog(_ data: Data) {
        log += String(bytes: data, encoding: .utf8) ?? ""
        if log.count > 20000 {
            log = String(log.suffix(16000))
        }
    }

    /// Exit status 0 is a normal finish; anything else, or a signal, is a crash unless we asked it to stop.
    func processEnded(status: Int32, wasSignalled: Bool) {
        watchdog?.invalidate()
        cancelRequests()
        guard !isStopping else { return }
        if status == 0, !wasSignalled {
            onMessage(["type": "exit"])
        } else if failure == nil {
            let message = wasSignalled
                ? String(localized: "The extension stopped unexpectedly. It was killed by signal \(status).", bundle: .floe, comment: "The placeholder is a number.")
                : String(localized: "The extension stopped unexpectedly. It exited with status \(status).", bundle: .floe, comment: "The placeholder is a number.")
            failure = SessionFailure(kind: .crashed, message: message, details: log)
            onMessage(["type": "crashed"])
        }
    }

    /// One watchdog tick: sends a ping, or reports the host as not responding when the last ping
    /// has gone unanswered for more than 8 seconds.
    func heartbeat(now: Date = Date()) {
        if let sent = pingSentAt {
            if now.timeIntervalSince(sent) > 8, failure == nil {
                failure = SessionFailure(kind: .unresponsive, message: String(localized: "The extension isn't responding.", bundle: .floe), details: log)
            }
            return
        }
        pingSentAt = now
        send(["type": "ping"])
    }

    // MARK: Derived view state

    var screen: Node? {
        ViewState.screen(in: root)
    }

    var view: Node? {
        ViewState.view(in: root)
    }

    var isList: Bool {
        ViewState.isList(view)
    }

    /// A render that kept every row leaves `rows` alone, and with it the views that draw them.
    private func recomputeRows() {
        let next = ViewState.rows(of: view, searchText: searchText)
        guard next != rows else { return }
        rows = next
        rowsVersion += 1
    }

    var selectedRow: Row? {
        ViewState.selectedRow(rows, selection: selection)
    }

    var actionPanel: Node? {
        ViewState.actionPanel(view: view, selectedRow: selectedRow)
    }

    var actions: [Node] {
        ViewState.actions(in: actionPanel)
    }

    var menuEntries: [MenuEntry] {
        ViewState.menuEntries(in: actionPath.last ?? actionPanel, query: actionQuery)
    }

    /// Keeps the open submenus only while they still exist, and as this render has them: the path
    /// holds nodes of the render they were opened in.
    private func refreshActionPath() {
        let submenus = actionPanel?.descendants(ofType: "ActionPanel.Submenu") ?? []
        let current = actionPath.compactMap { open in submenus.first { $0.id == open.id } }
        if current.count != actionPath.count {
            actionPath = []
        } else if current.map(\.revision) != actionPath.map(\.revision) {
            actionPath = current
        }
    }

    func openSubmenu(_ submenu: Node) {
        if submenu.handlers.contains("onOpen") {
            event(submenu, "onOpen")
        }
        actionPath.append(submenu)
        actionQuery = ""
        actionSelection = 0
    }

    /// Esc and ← step out of a submenu before closing the menu.
    func closeSubmenuOrMenu() {
        if !actionQuery.isEmpty {
            actionQuery = ""
        } else if actionPath.isEmpty {
            actionMenuOpen = false
        } else {
            actionPath.removeLast()
            actionSelection = 0
        }
    }

    func activateMenuEntry(at index: Int) {
        let entries = menuEntries
        guard entries.indices.contains(index) else { return }
        if entries[index].isSubmenu {
            openSubmenu(entries[index].node)
        } else {
            run(entries[index].node)
        }
    }

    func run(_ action: Node) {
        actionMenuOpen = false
        if action.bool("isSubmit") {
            if action.handlers.contains("onSubmit") {
                event(action, "onSubmit", [ViewState.submittedValues(of: view, typed: formValues)])
            }
        } else if action.handlers.contains("onAction") {
            event(action, "onAction")
        }
    }
}

// MARK: Forms and selection

extension ExtensionSession {
    func formValue(_ field: Node) -> Any? {
        ViewState.formValue(field, typed: formValues)
    }

    func setFormValue(_ field: Node, _ value: Any) {
        guard let id = field.props["id"] as? String else { return }
        formValues[id] = value
        if field.handlers.contains("onChange") {
            event(field, "onChange", [ViewState.wireValue(value, field: field)])
        }
    }

    /// Moves within the action menu when it's open, else the list; large steps stop at the ends.
    func moveSelection(by delta: Int) {
        if actionMenuOpen {
            actionSelection = ViewState.clamp(actionSelection + delta, count: menuEntries.count)
        } else {
            selection = ViewState.clamp(min(selection, rows.count - 1) + delta, count: rows.count)
        }
    }
}
