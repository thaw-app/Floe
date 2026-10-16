//
//  ExtensionRunnerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The runner on its own, with a host that records what it was asked: no launcher and no Bun process.
@MainActor
struct ExtensionRunnerTests {
    private final class Asked {
        var calls: [String] = []
    }

    private let asked = Asked()

    private func runner(runsElsewhere: Bool = false) -> ExtensionRunner {
        let runner = ExtensionRunner()
        let asked = asked
        runner.host = ExtensionRunner.Host(
            showPanel: { asked.calls.append("show") },
            hidePanel: { asked.calls.append("hide") },
            showHUD: { asked.calls.append("hud \($0)") },
            refocus: { asked.calls.append("refocus") },
            beginSetup: { asked.calls.append("setup \($0.kind)") },
            toggleMenuBar: { asked.calls.append("menu bar \($0.name)") },
            runElsewhere: { command, _ in
                if runsElsewhere {
                    asked.calls.append("elsewhere \(command.name)")
                }
                return runsElsewhere
            },
            open: { target, application in asked.calls.append("open \(target) \(application ?? "-")") }
        )
        return runner
    }

    private func command(mode: String = "view", arguments: [FieldSpec] = []) -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/floe-runner-tests"), extensionName: "floe-runner-tests",
            extensionTitle: "Tests", source: .local, name: "greet", title: "Greet",
            mode: mode, interval: nil, icon: nil, arguments: arguments, extensionPreferences: [], commandPreferences: []
        )
    }

    @Test func aRunHandedToAnotherProcessStartsNothingHere() {
        let runner = runner(runsElsewhere: true)
        runner.run(command())
        #expect(asked.calls == ["elsewhere greet"])
        #expect(runner.session == nil)
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
}
