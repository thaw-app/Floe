//
//  SSHConnection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What opening a connection needs from this Mac. Tests pass their own, so none opens or runs anything.
nonisolated struct SSHConnector: Sendable {
    var bundleIdentifier: @Sendable (URL) -> String?
    /// Whether an app's Info.plist says it answers "ssh://" links.
    var takesSSHLinks: @Sendable (URL) -> Bool
    /// Where the system's Terminal is, for a terminal Floe has no way to hand a command to.
    var systemTerminal: @Sendable () -> URL?
    var open: @MainActor @Sendable (Handoff) -> Void
    var runScript: AppleScriptRunner

    static let system = SSHConnector(
        bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier },
        takesSSHLinks: { SSHConnection.linkSchemes(in: Bundle(url: $0)?.infoDictionary).contains("ssh") },
        systemTerminal: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppRole.systemTerminal) },
        open: { PreferredApps.open($0) },
        runScript: AppleScript.run
    )
}

/// How one connection is opened, decided before anything is.
nonisolated struct SSHConnectionPlan: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        /// An "ssh://" link, opened with the terminal that answers it.
        case link(Handoff)
        /// A script that tells the terminal to run the command.
        case script(String)
        /// Nothing is opened; `notice` says why.
        case nothing
    }

    var step: Step
    /// The terminal's name, for what is said when it refuses or fails.
    var app = ""
    /// A line for the HUD, whatever the step.
    var notice: String?
}

/// How opening a connection ended.
nonisolated enum SSHConnectionOutcome: Equatable, Sendable {
    /// Opened, or not: the line for the HUD when there is something to say.
    case finished(String?)
    /// macOS did not let Floe control the terminal.
    case automationRefused(app: String)
}

/// Hands "ssh" and a host's alias to a terminal. Floe opens no connection itself.
nonisolated enum SSHConnection {
    /// Read from Ghostty 1.3.1's Info.plist. It registers no "ssh://" link; its scripting dictionary opens windows.
    static let ghostty = "com.mitchellh.ghostty"

    static let unsafeAliasNotice = String(localized: "Not connected. Floe only passes on host names made of letters, digits, dots, hyphens and underscores.", bundle: .floe)
    static let noTerminalNotice = String(localized: "Not connected. Choose a terminal in Floe Settings.", bundle: .floe)

    /// An alias that can go into a link or a script as it is: a line in the configuration must not
    /// become an option of ssh or a second command.
    static func isSafe(_ alias: String) -> Bool {
        guard let first = alias.unicodeScalars.first, alias.unicodeScalars.count <= 253 else { return false }
        let isPlain: (Unicode.Scalar) -> Bool = { scalar in
            ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar) || ("0" ... "9").contains(scalar)
        }
        return (isPlain(first) || first == "_") && alias.unicodeScalars.allSatisfy { isPlain($0) || "._-".unicodeScalars.contains($0) }
    }

    /// What Copy SSH Command copies. An alias that is not safe as it is goes in quotes, after the
    /// "--" that ends ssh's options.
    static func command(for alias: String) -> String {
        isSafe(alias) ? "ssh \(alias)" : "ssh -- '\(alias.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// The link a terminal that answers "ssh://" opens. The alias is the host, so the configuration applies to it.
    static func link(to alias: String) -> URL? {
        guard isSafe(alias) else { return nil }
        var components = URLComponents()
        components.scheme = "ssh"
        components.host = alias
        return components.url
    }

    /// The link schemes an app's Info.plist registers, in lower case.
    static func linkSchemes(in info: [String: Any]?) -> [String] {
        let types = info?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
    }

    /// Terminal's own way to run a command, from its scripting dictionary: a new window that runs it.
    static func terminalScript(alias: String) -> String {
        """
        tell application id \(AppleScript.literal(AppRole.systemTerminal))
            activate
            do script \(AppleScript.literal(command(for: alias)))
        end tell
        """
    }

    /// Ghostty's, from the scripting dictionary in its bundle: a new window whose shell is typed the command.
    static func ghosttyScript(alias: String) -> String {
        """
        tell application id \(AppleScript.literal(ghostty))
            activate
            new window with configuration {initial input:\(AppleScript.literal(command(for: alias))) & linefeed}
        end tell
        """
    }

    /// The terminal's own way first; the system's Terminal, and a line that says so, for a terminal
    /// with none; nothing at all for an alias that is not safe.
    static func plan(alias: String, terminal: ResolvedApp?, using connector: SSHConnector) -> SSHConnectionPlan {
        guard isSafe(alias) else { return SSHConnectionPlan(step: .nothing, notice: unsafeAliasNotice) }
        if let terminal, let step = step(alias: alias, app: terminal.url, using: connector) {
            return SSHConnectionPlan(step: step, app: terminal.name)
        }
        guard let fallback = connector.systemTerminal(), fallback != terminal?.url,
              let step = step(alias: alias, app: fallback, using: connector)
        else { return SSHConnectionPlan(step: .nothing, notice: noTerminalNotice) }
        let name = ResolvedApp(url: fallback).name
        let notice = terminal.map { String(localized: "\($0.name) takes no command from Floe, so the connection opened in \(name)", bundle: .floe, comment: "Both placeholders are names of terminal apps.") }
        return SSHConnectionPlan(step: step, app: name, notice: notice)
    }

    /// How one app is handed the command; nil when Floe knows no way that was verified for it.
    private static func step(alias: String, app: URL, using connector: SSHConnector) -> SSHConnectionPlan.Step? {
        if connector.takesSSHLinks(app), let link = link(to: alias) {
            return .link(Handoff(urls: [link], application: app))
        }
        switch connector.bundleIdentifier(app) {
        case AppRole.systemTerminal: return .script(terminalScript(alias: alias))
        case ghostty: return .script(ghosttyScript(alias: alias))
        default: return nil
        }
    }

    /// Carries the plan out. A script waits for the terminal, so it runs off the main thread.
    @MainActor
    static func open(_ plan: SSHConnectionPlan, using connector: SSHConnector) async -> SSHConnectionOutcome {
        switch plan.step {
        case .nothing:
            return .finished(plan.notice)
        case let .link(handoff):
            connector.open(handoff)
            return .finished(plan.notice)
        case let .script(source):
            switch await run(source, with: connector.runScript) {
            case .text: return .finished(plan.notice)
            case .refused: return .automationRefused(app: plan.app)
            case .failed: return .finished(String(localized: "Couldn't open the connection in \(plan.app)", bundle: .floe, comment: "The placeholder is the name of a terminal app."))
            }
        }
    }

    /// Return on a host: decides, opens, and says what there is to say. The task is for tests to wait on.
    @discardableResult
    static func connect(
        to host: SSHHost,
        terminal: ResolvedApp?,
        using connector: SSHConnector,
        showHUD: @escaping @MainActor @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        let plan = plan(alias: host.alias, terminal: terminal, using: connector)
        let lease = PanelWork.begin()
        return Task { @MainActor in
            defer { withExtendedLifetime(lease) {} }
            switch await open(plan, using: connector) {
            case let .finished(notice):
                if let notice {
                    showHUD(notice)
                }
            case let .automationRefused(app):
                SystemCommand.askForAutomation(toControl: app)
            }
        }
    }

    @concurrent
    private static func run(_ source: String, with runner: AppleScriptRunner) async -> AppleScriptOutcome {
        await runner(source)
    }
}

/// The Actions menu of a host, after Connect.
enum SSHHostActions {
    /// `copy` is a parameter so a test can read what would be copied.
    static func actions(
        for host: SSHHost,
        host actionHost: ActionHost,
        copy: @escaping (String) -> Void = { NSPasteboard.general.copy($0) }
    ) -> [ItemAction?] {
        let command = SSHConnection.command(for: host.alias)
        return [
            nil,
            ItemAction(title: String(localized: "Copy Host Name", bundle: .floe), symbol: "doc.on.doc") {
                copy(host.copyableName)
                actionHost.showHUD(String(localized: "Copied \(host.copyableName)", bundle: .floe, comment: "The placeholder is the text that was copied."))
            },
            ItemAction(title: String(localized: "Copy SSH Command", bundle: .floe), symbol: "terminal") {
                copy(command)
                actionHost.showHUD(String(localized: "Copied \(command)", bundle: .floe, comment: "The placeholder is the text that was copied."))
            },
        ]
    }
}
