//
//  ExtensionRunnerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import AppKit
import Testing

/// The runner on its own, with a host that records what it was asked: no launcher and no Bun process.
@MainActor
struct ExtensionRunnerTests {
    private final class Asked {
        var calls: [String] = []
    }

    private let asked = Asked()

    private func runner(panelShown: Bool = false) -> ExtensionRunner {
        let runner = ExtensionRunner()
        let asked = asked
        runner.host = ExtensionRunner.Host(
            showPanel: { asked.calls.append("show") },
            hidePanel: { asked.calls.append("hide") },
            showHUD: { asked.calls.append("hud \($0)") },
            refocus: { asked.calls.append("refocus") },
            isPanelShown: { panelShown },
            beginSetup: { asked.calls.append("setup \($0.kind)") },
            toggleMenuBar: { asked.calls.append("menu bar \($0.name)") },
            open: { target, application in asked.calls.append("open \(target) \(application ?? "-")") },
            showPreferences: { message, _ in asked.calls.append("preferences \(message["type"] as? String ?? "")") }
        )
        return runner
    }

    private func command(mode: String = "view", arguments: [FieldSpec] = [], preferences: [FieldSpec] = []) -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/floe-runner-tests"), extensionName: "floe-runner-tests",
            extensionTitle: "Tests", source: .local, name: "greet", title: "Greet",
            mode: mode, interval: nil, icon: nil, arguments: arguments, extensionPreferences: [], commandPreferences: preferences
        )
    }

    /// A toast from the host, as the session receives it: it keeps the toast, then hands the message on.
    private func toast(_ session: ExtensionSession) {
        var kept = KeptRender()
        let line = Data(#"{"type":"toast","id":1,"style":"success","title":"Done"}"#.utf8)
        if let message = DecodedHostMessage.decode(line, kept: &kept) {
            session.apply(message)
        }
    }

    /// A pasteboard of the test's own, so the user's clipboard is never written.
    private func withPasteboard(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        body(pasteboard)
    }

    /// A runner whose sessions start no host, handed out as they are made: the test plays the host.
    private func reloadingRunner() -> (ExtensionRunner, () -> [ExtensionSession]) {
        let runner = runner()
        var started: [ExtensionSession] = []
        runner.startsHost = { started.append($0) }
        runner.run(command())
        return (runner, { started })
    }

    private func render(_ session: ExtensionSession) {
        var kept = KeptRender()
        let line = Data(#"{"type":"render","sequence":1,"tree":{"id":1,"type":"List","props":{},"handlers":[],"children":[]}}"#.utf8)
        if let message = DecodedHostMessage.decode(line, kept: &kept) {
            session.apply(message)
        }
    }

    @Test func aSavedChangeTakesOverOnceItShowsSomething() throws {
        let (runner, started) = reloadingRunner()
        let first = try #require(runner.session)
        render(first)
        runner.reload(first, changed: ["src/index.tsx"])
        #expect(started().count == 2)
        #expect(runner.session === first, "the view on screen stays while the change starts")
        render(started()[1])
        #expect(runner.session === started()[1])
    }

    @Test func aSavedChangeThatFailsLeavesTheLastViewUpAndSaysWhy() throws {
        let (runner, started) = reloadingRunner()
        let first = try #require(runner.session)
        render(first)
        runner.reload(first, changed: ["src/index.tsx"])
        started()[1].failure = SessionFailure(kind: .error, message: "Expected \";\" but found \"}\"", details: "")
        #expect(runner.session === first)
        #expect(first.toast?.title == "The change didn't load")
        #expect(first.toast?.message == "Expected \";\" but found \"}\"")
        render(started()[1])
        #expect(runner.session === first, "the failed change is gone")
    }

    @Test func aViewThatFailedGivesWayToTheNextFailure() throws {
        let (runner, started) = reloadingRunner()
        let first = try #require(runner.session)
        first.failure = SessionFailure(kind: .error, message: "first", details: "")
        runner.reload(first, changed: ["src/index.tsx"])
        started()[1].failure = SessionFailure(kind: .error, message: "second", details: "")
        #expect(runner.session === started()[1])
    }

    @Test func aMenuBarCommandIsPutInTheMenuBarInsteadOfRun() {
        let runner = runner()
        runner.run(command(mode: "menu-bar"))
        #expect(asked.calls == ["menu bar greet"])
        #expect(runner.session == nil)
    }

    @Test func aCommandThatTakesArgumentsAsksForThemFirst() throws {
        let runner = runner()
        let name = try JSONDecoder().decode(FieldSpec.self, from: Data(#"{"name":"name","type":"text","required":true}"#.utf8))
        runner.run(command(arguments: [name]))
        #expect(asked.calls == ["setup arguments"])
        #expect(runner.session == nil)
    }

    @Test func whatABackgroundRunAsksForIsSaidOrOpenedAndNeverShowsThePanel() {
        let runner = runner()
        runner.handleBackgroundMessage(["type": "hud", "title": "Done"])
        runner.handleBackgroundMessage(["type": "open", "target": "https://example.com", "application": "Safari"])
        runner.handleBackgroundMessage(["type": "unknown"])
        #expect(asked.calls == ["hud Done", "open https://example.com Safari"])
    }

    @Test func aSessionThatIsNotTheOpenOneEndsWithoutTakingTheKeysBack() {
        let runner = runner()
        let other = ExtensionSession(command: command())
        runner.end(other)
        runner.endOpenCommand()
        #expect(asked.calls.isEmpty)
    }

    @Test func aCommandMissingARequiredPreferenceAsksForItFirst() throws {
        let runner = runner()
        let token = try JSONDecoder().decode(FieldSpec.self, from: Data(#"{"name":"floeRunnerTestsToken","type":"textfield","required":true}"#.utf8))
        runner.run(command(preferences: [token]))
        #expect(asked.calls == ["setup preferences"])
        #expect(runner.session == nil)
    }

    @Test func withNoOpenCommandRetryingOrCopyingTheFailureDoesNothing() {
        let runner = runner()
        runner.retry()
        runner.copyFailure()
        #expect(asked.calls.isEmpty)
    }

    @Test func aCommandThatIsNotTheOpenOneExitsWithoutHidingThePanelAndSaysWhenItCrashes() {
        let runner = runner()
        runner.handle(["type": "exit"], from: ExtensionSession(command: command(mode: "no-view")))
        runner.handle(["type": "exit"], from: ExtensionSession(command: command()))
        runner.handle(["type": "crashed"], from: ExtensionSession(command: command(mode: "no-view")))
        #expect(asked.calls == ["hud Greet failed"], "one launched in the background by another leaves the panel to the command on screen")
    }

    @Test func whatACommandAsksForReachesTheHost() {
        let runner = runner()
        let session = ExtensionSession(command: command())
        runner.handle(["type": "close"], from: session)
        runner.handle(["type": "hud", "title": "Saved"], from: session)
        runner.handle(["type": "open", "target": "/tmp/file.txt"], from: session)
        runner.handle(["type": "signIn"], from: session)
        #expect(asked.calls == ["hide", "hud Saved", "hide", "open /tmp/file.txt -", "preferences signIn"])
    }

    @Test func aCopyIsWrittenConcealedWhenAskedAndABackgroundCopyToo() {
        withPasteboard { pasteboard in
            let runner = runner()
            runner.pasteboard = pasteboard
            runner.handle(["type": "copy", "text": "hunter2", "concealed": true], from: ExtensionSession(command: command()))
            #expect(pasteboard.string(forType: .string) == "hunter2")
            guard case .skipped = ClipboardCapture.reading(pasteboard) else {
                Issue.record("the copy asked to be concealed was not")
                return
            }

            runner.handleBackgroundMessage(["type": "copy", "text": "from the background"])
            #expect(pasteboard.string(forType: .string) == "from the background")
            #expect(asked.calls.isEmpty)
        }
    }

    @Test func aToastFromACommandWithoutAViewIsSaidOnceAsAHUD() {
        let runner = runner()
        let session = ExtensionSession(command: command(mode: "no-view"))
        session.onMessage = { runner.handle($0, from: session) }
        toast(session)
        toast(session)
        #expect(asked.calls == ["hud Done"])
    }

    @Test func aToastFromAViewOnScreenStaysInItsFooter() {
        let runner = runner(panelShown: true)
        let session = ExtensionSession(command: command())
        session.onMessage = { runner.handle($0, from: session) }
        toast(session)
        #expect(asked.calls.isEmpty)
    }
}
