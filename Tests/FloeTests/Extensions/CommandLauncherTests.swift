//
//  CommandLauncherTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct CommandLauncherTests {
    private final class Started {
        var userInitiated: [(id: String, arguments: [String: Any], context: [String: Any]?)] = []
        var background: [(id: String, arguments: [String: Any], context: [String: Any]?)] = []
    }

    private let caller = Fixture.command("inbox", extension: "mail")
    private let compose = Fixture.command("compose", extension: "mail")
    private let unread = Fixture.command("unread", extension: "mail", mode: "no-view")
    private let forecast = Fixture.command("forecast", extension: "weather")
    private let started = Started()

    private func launcher() -> CommandLauncher {
        CommandLauncher(
            commands: { [caller, compose, unread, forecast] in [caller, compose, unread, forecast] },
            userInitiated: { [started] in started.userInitiated.append(($0.id, $1, $2)) },
            background: { [started] in started.background.append(($0.id, $1, $2)) }
        )
    }

    @Test func aCommandOfTheSameExtensionStartsAsTheUserWouldWithItsArgumentsAndContext() throws {
        try launcher().launch(["name": "compose", "type": "userInitiated", "arguments": ["to": "a@b.c"], "context": ["draft": 7]], from: caller)
        let launch = try #require(started.userInitiated.first)
        #expect(launch.id == "mail/compose")
        #expect(launch.arguments["to"] as? String == "a@b.c")
        #expect(launch.context?["draft"] as? Int == 7)
        #expect(started.background.isEmpty)
    }

    @Test func anotherExtensionsCommandIsFoundByItsExtensionsName() throws {
        try launcher().launch(["name": "forecast", "extensionName": "weather"], from: caller)
        #expect(started.userInitiated.map(\.id) == ["weather/forecast"], "no type is the user's")
    }

    @Test func theBackgroundTypeRunsANoViewCommandAndRefusesAView() throws {
        try launcher().launch(["name": "unread", "type": "background"], from: caller)
        #expect(started.background.map(\.id) == ["mail/unread"])
        #expect(throws: RequestRefusal.self) { try launcher().launch(["name": "compose", "type": "background"], from: caller) }
    }

    @Test func aCommandThatIsNotThereIsRefusedWithWhy() {
        #expect(throws: RequestRefusal.self) { try launcher().launch([:], from: caller) }
        #expect(throws: RequestRefusal.self) { try launcher().launch(["name": "gone"], from: caller) }
        #expect(throws: RequestRefusal.self) { try launcher().launch(["name": "inbox", "extensionName": "weather"], from: caller) }
        #expect(started.userInitiated.isEmpty)
    }

    @Test func theSessionRepliesOnceTheCommandStartedOrWithTheReason() throws {
        let session = ExtensionSession(command: caller)
        var sent: [[String: Any]] = []
        session.transport = { sent.append($0) }
        let previous = CommandLauncher.shared
        defer { CommandLauncher.shared = previous }

        CommandLauncher.shared = launcher()
        _ = session.handleRequest(["type": "request", "id": 4, "method": "command.launch", "params": ["name": "compose"]])
        _ = session.handleRequest(["type": "request", "id": 5, "method": "command.launch", "params": ["name": "gone"]])
        #expect(sent.count == 2)
        #expect(sent.first?["id"] as? Int == 4)
        #expect(sent.first?["result"] is NSNull)
        #expect((sent.last?["error"] as? String)?.contains("gone") == true)

        CommandLauncher.shared = nil
        _ = session.handleRequest(["type": "request", "id": 6, "method": "command.launch", "params": ["name": "compose"]])
        #expect(sent.last?["error"] as? String == "Floe can't launch commands from here.")
    }

    @Test func theContextReachesTheHostAsJSON() throws {
        let variables = ExtensionSession.hostVariables([:], preferences: nil, hasAI: false, launch: ("userInitiated", ["draft": 7]))
        #expect(variables["FLOE_LAUNCH_CONTEXT"] == #"{"draft":7}"#)
        #expect(ExtensionSession.hostVariables([:], preferences: nil, hasAI: false)["FLOE_LAUNCH_CONTEXT"] == nil)
    }
}
