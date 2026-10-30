//
//  SSHConnectionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Terminals that are on no Mac, so no test opens the one it runs on.
private nonisolated enum Fake {
    static let terminal = URL(fileURLWithPath: "/Fake/System/Terminal.app")
    static let ghostty = URL(fileURLWithPath: "/Fake/Applications/Ghostty.app")
    static let other = URL(fileURLWithPath: "/Fake/Applications/Hyper.app")
    static let identifiers = [terminal: "com.apple.Terminal", ghostty: "com.mitchellh.ghostty", other: "dev.example.hyper"]
}

/// What a connection opened and ran, from any thread. Nothing here reaches an app.
private final nonisolated class Handed: @unchecked Sendable {
    private let lock = NSLock()
    private var handoffs: [Handoff] = []
    private var sources: [String] = []
    private var lines: [String] = []

    var opened: [Handoff] {
        lock.withLock { handoffs }
    }

    var scripts: [String] {
        lock.withLock { sources }
    }

    var hud: [String] {
        lock.withLock { lines }
    }

    func open(_ handoff: Handoff) {
        lock.withLock { handoffs.append(handoff) }
    }

    func run(_ source: String) {
        lock.withLock { sources.append(source) }
    }

    func show(_ line: String) {
        lock.withLock { lines.append(line) }
    }
}

@MainActor
struct SSHConnectionTests {
    private let handed = Handed()

    /// A Mac where these apps answer "ssh://" links, with or without a system Terminal.
    private func connector(links: Set<URL> = [], systemTerminal: URL? = Fake.terminal, script: AppleScriptOutcome = .text("")) -> SSHConnector {
        SSHConnector(
            bundleIdentifier: { Fake.identifiers[$0] },
            takesSSHLinks: { links.contains($0) },
            systemTerminal: { systemTerminal },
            open: { [handed] in handed.open($0) },
            runScript: { [handed] source in
                handed.run(source)
                return script
            }
        )
    }

    private func plan(_ alias: String, in terminal: URL?, _ connector: SSHConnector) -> SSHConnectionPlan {
        SSHConnection.plan(alias: alias, terminal: terminal.map(ResolvedApp.init), using: connector)
    }

    private func script(_ plan: SSHConnectionPlan) -> String? {
        if case let .script(source) = plan.step {
            return source
        }
        return nil
    }

    // MARK: Which way

    @Test func aTerminalThatAnswersSSHLinksIsHandedOne() throws {
        let plan = plan("web-1.example", in: Fake.other, connector(links: [Fake.other]))
        let link = try #require(URL(string: "ssh://web-1.example"))
        #expect(plan == SSHConnectionPlan(step: .link(Handoff(urls: [link], application: Fake.other)), app: "Hyper"))
        #expect(plan.notice == nil)
    }

    @Test func theLinkCarriesTheAliasAsItIsWritten() {
        #expect(SSHConnection.link(to: "My_Host.example-1")?.absoluteString == "ssh://My_Host.example-1")
    }

    @Test func anAppsLinkSchemesAreReadFromItsInfoPlist() {
        let info: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": ["telnet"]], ["CFBundleURLName": "ssh URL", "CFBundleURLSchemes": ["SSH"]]]]
        #expect(SSHConnection.linkSchemes(in: info) == ["telnet", "ssh"])
        #expect(SSHConnection.linkSchemes(in: ["CFBundleName": "Ghostty"]).isEmpty)
        #expect(SSHConnection.linkSchemes(in: nil).isEmpty)
    }

    @Test func terminalWithoutTheLinkIsToldToRunTheCommand() throws {
        let plan = plan("web", in: Fake.terminal, connector())
        let source = try #require(script(plan))
        #expect(source.contains(#"tell application id "com.apple.Terminal""#))
        #expect(source.contains(#"do script "ssh web""#))
        #expect(plan.app == "Terminal")
        #expect(plan.notice == nil)
    }

    @Test func ghosttyIsToldToOpenAWindowThatIsTypedTheCommand() throws {
        let plan = plan("web", in: Fake.ghostty, connector())
        let source = try #require(script(plan))
        #expect(source.contains(#"tell application id "com.mitchellh.ghostty""#))
        #expect(source.contains(#"new window with configuration {initial input:"ssh web" & linefeed}"#))
        #expect(plan.app == "Ghostty")
    }

    @Test func aTerminalWithNoWayInGivesWayToTerminalAndSaysSo() throws {
        let link = try #require(URL(string: "ssh://web"))
        let viaLink = plan("web", in: Fake.other, connector(links: [Fake.terminal]))
        #expect(viaLink.step == .link(Handoff(urls: [link], application: Fake.terminal)))
        #expect(viaLink.notice == "Hyper takes no command from Floe, so the connection opened in Terminal")
        #expect(viaLink.app == "Terminal")

        let viaScript = plan("web", in: Fake.other, connector())
        #expect(script(viaScript)?.contains(#"do script "ssh web""#) == true)
        #expect(viaScript.notice == "Hyper takes no command from Floe, so the connection opened in Terminal")
    }

    @Test func withNoTerminalAtAllNothingIsOpenedAndTheLineSaysWhatToDo() {
        let none = SSHConnectionPlan(step: .nothing, notice: "Not connected. Choose a terminal in Floe Settings.")
        #expect(plan("web", in: Fake.other, connector(systemTerminal: nil)) == none)
        #expect(plan("web", in: nil, connector(systemTerminal: nil)) == none)
    }

    @Test func withoutAChosenTerminalTheSystemsIsUsedAndNothingIsSaid() {
        let plan = plan("web", in: nil, connector(links: [Fake.terminal]))
        #expect(plan.app == "Terminal")
        #expect(plan.notice == nil)
    }

    // MARK: An alias that is not safe

    @Test(arguments: ["-oProxyCommand=open.-a.Calculator", "web;id", "web id", "$(id)", "`id`", "web\"", "web'", "web\\", "a/b", "web\nid", "user@web", "wéb", "", ".web", String(repeating: "a", count: 254)])
    func anAliasThatCouldBecomeACommandIsRefused(alias: String) async {
        #expect(!SSHConnection.isSafe(alias))
        #expect(SSHConnection.link(to: alias) == nil)
        let connector = connector(links: [Fake.terminal, Fake.ghostty, Fake.other])
        for terminal in [Fake.terminal, Fake.ghostty, Fake.other, nil] {
            let plan = plan(alias, in: terminal, connector)
            #expect(plan.step == .nothing)
            #expect(plan.notice == "Not connected. Floe only passes on host names made of letters, digits, dots, hyphens and underscores.")
        }
        await SSHConnection.connect(to: SSHHost(alias: alias), terminal: ResolvedApp(url: Fake.terminal), using: connector) { [handed] in handed.show($0) }.value
        #expect(handed.opened.isEmpty)
        #expect(handed.scripts.isEmpty)
        #expect(handed.hud == [SSHConnection.unsafeAliasNotice])
    }

    @Test(arguments: ["web", "web-1.example.com", "My_Host", "10.0.0.5", "_gateway", "a"])
    func anOrdinaryAliasIsSafe(alias: String) {
        #expect(SSHConnection.isSafe(alias))
    }

    @Test func theCommandToCopyQuotesAnAliasThatIsNotSafe() {
        #expect(SSHConnection.command(for: "web") == "ssh web")
        #expect(SSHConnection.command(for: "-v") == "ssh -- '-v'")
        #expect(SSHConnection.command(for: "it's;id") == #"ssh -- 'it'\''s;id'"#)
        #expect(SSHConnection.command(for: "it'\u{0301};id") == "ssh -- 'it'\\''\u{0301};id'")
    }

    // MARK: Opening

    @Test func aLinkIsOpenedWithItsTerminalAndNoScriptRuns() async throws {
        let connector = connector(links: [Fake.other])
        let outcome = await SSHConnection.open(plan("web", in: Fake.other, connector), using: connector)
        #expect(outcome == .finished(nil))
        #expect(try handed.opened == [Handoff(urls: [#require(URL(string: "ssh://web"))], application: Fake.other)])
        #expect(handed.scripts.isEmpty)
    }

    @Test func aScriptIsRunAndNothingIsOpenedBesides() async {
        let connector = connector()
        let plan = plan("web", in: Fake.terminal, connector)
        #expect(await SSHConnection.open(plan, using: connector) == .finished(nil))
        #expect(handed.scripts == [SSHConnection.terminalScript(alias: "web")])
        #expect(handed.opened.isEmpty)
    }

    @Test func aRefusedScriptAsksForAutomationAndAFailedOneSaysWhere() async {
        let refusing = connector(script: .refused)
        #expect(await SSHConnection.open(plan("web", in: Fake.ghostty, refusing), using: refusing) == .automationRefused(app: "Ghostty"))
        let failing = connector(script: .failed)
        #expect(await SSHConnection.open(plan("web", in: Fake.terminal, failing), using: failing) == .finished("Couldn't open the connection in Terminal"))
    }

    @Test func connectingThroughTheFallbackShowsItsLine() async {
        let connector = connector(links: [Fake.terminal])
        await SSHConnection.connect(to: SSHHost(alias: "web"), terminal: ResolvedApp(url: Fake.other), using: connector) { [handed] in handed.show($0) }.value
        #expect(handed.opened.map(\.application) == [Fake.terminal])
        #expect(handed.hud == ["Hyper takes no command from Floe, so the connection opened in Terminal"])
    }

    @Test func connectingTheOrdinaryWaySaysNothing() async {
        let connector = connector(links: [Fake.terminal])
        await SSHConnection.connect(to: SSHHost(alias: "web", hostName: "10.0.0.5"), terminal: ResolvedApp(url: Fake.terminal), using: connector) { [handed] in handed.show($0) }.value
        #expect(handed.opened.flatMap(\.urls).map(\.absoluteString) == ["ssh://web"], "the alias is handed over, so the configuration applies")
        #expect(handed.hud.isEmpty)
    }
}
