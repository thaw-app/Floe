//
//  WhatLeavesTheMainActorTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing

/// A scanner with no actor of its own, so each scan runs wherever the model's task put it.
private nonisolated struct ThreadScanner: CatalogScanning {
    let log: ThreadLog

    func scanApps() async -> [AppEntry] {
        log.note("apps")
        return []
    }

    func scanCommands(includeRaycast _: Bool) async -> [ExtensionCommand] {
        log.note("commands")
        return []
    }

    func scanScripts() async -> ScriptScan {
        log.note("scripts")
        return ScriptScan()
    }

    func scanSettingsPanes() async -> [SystemSettingsPane] {
        log.note("panes")
        return []
    }

    func scanSSHHosts() async -> [SSHHost] {
        log.note("hosts")
        return []
    }
}

/// Every call here starts on the main actor, as it does in the app. Unmarked async code runs where it
/// is called, so each of these would run on the main thread if it lost its `@concurrent`.
@MainActor
struct WhatLeavesTheMainActorTests {
    private let scratch: ScratchDefaults
    private let log = ThreadLog()

    init() throws {
        scratch = ScratchDefaults()
    }

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 5000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    // MARK: The catalog

    @Test func theLaunchersScansRunOffTheMainThread() async {
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        let model = LauncherModel(scanner: ThreadScanner(log: log), settings: settings, usage: UsageStore(defaults: scratch.defaults), sources: [])
        model.startCatalogLoading()
        await model.catalog.reloadSSHHosts().value
        await waitFor("the five scans") { log.onMain.count == 5 }
        #expect(log.onMain == ["apps": false, "commands": false, "scripts": false, "panes": false, "hosts": false])
    }

    @Test func theSettingsWindowsScansRunOffTheMainThread() async {
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        let catalog = CatalogStore(scanner: ThreadScanner(log: log), settings: settings)
        catalog.reloadAll()
        await waitFor("the three scans") { log.onMain.count == 3 }
        #expect(log.onMain == ["apps": false, "commands": false, "scripts": false])
    }

    // MARK: Tools and scripts

    @Test func aTerminalsScriptRunsOffTheMainThread() async {
        let connector = SSHConnector(
            bundleIdentifier: { _ in nil },
            takesSSHLinks: { _ in false },
            systemTerminal: { nil },
            open: { _ in },
            runScript: { [log] _ in
                log.note("script")
                return .text("")
            }
        )
        let outcome = await SSHConnection.open(SSHConnectionPlan(step: .script("return 1"), app: "Terminal"), using: connector)
        #expect(outcome == .finished(nil))
        #expect(log.onMain == ["script": false])
    }

    @Test func theShortcutsToolIsAskedOffTheMainThread() async {
        let tool = ShortcutsTool { [log] arguments in
            log.note(arguments.first ?? "")
            return ShortcutsToolResult(succeeded: true)
        }
        let shortcut = AppleShortcut(name: "Resize Image", identifier: "7E1D2C3B-4A5F-4E6D-8C7B-9A0F1E2D3C4B")
        #expect(await tool.list() == [])
        #expect(await tool.run(shortcut) == nil)
        #expect(await tool.view(shortcut) == nil)
        #expect(log.onMain == ["list": false, "run": false, "view": false])
    }

    @Test func theShortcutLibraryListsAndRunsOffTheMainThread() async {
        let library = AppleShortcutLibrary()
        library.tool = ShortcutsTool { [log] arguments in
            log.note(arguments.first ?? "")
            return ShortcutsToolResult(succeeded: true)
        }
        let shortcut = AppleShortcut(name: "Resize Image", identifier: "7E1D2C3B-4A5F-4E6D-8C7B-9A0F1E2D3C4B")
        await library.refresh(isOn: true) { /* nothing is drawn here */ }?.value
        await library.run(shortcut) { _ in /* nothing fails here */ }.value
        await library.openInShortcuts(shortcut) { _ in /* nothing fails here */ }.value
        #expect(log.onMain == ["list": false, "run": false, "view": false])
    }

    @Test func aToolIsLookedUpOnThePathOffTheMainActor() async {
        // No tool has this name, so the run ends at the lookup and starts no process.
        let left = await CountingExecutor.departures { _ = try? await Shell.run(tool: "floe-no-such-tool-\(UUID().uuidString)", []) }
        #expect(left > 0)
    }

    // MARK: What an extension asks for

    @Test func anExtensionsRequestIsAnsweredOffTheMainActor() async {
        // A request that is not this function's to answer throws at once, having read nothing.
        let left = await CountingExecutor.departures {
            _ = try? await HostRequest.answer(.oauthGetTokens(providerId: "none")) { _ in /* nothing streams */ }
        }
        #expect(left > 0)
    }

    @Test func theSignInBrokerAnswersOffTheMainActor() async {
        // The same from the other side: the broker refuses what is not a sign-in request before it reads a token.
        let left = await CountingExecutor.departures {
            _ = try? await OAuthBroker.shared.perform(.selectedText, extensionName: "none")
        }
        #expect(left > 0)
    }

    // MARK: Answers

    @Test func aPromptIsAnsweredOffTheMainThread() async throws {
        let sources = AISources(
            api: { [log] _, _, _ in
                log.note("api")
                return "from the API"
            },
            appleIntelligence: { [log] _, _ in
                log.note("appleIntelligence")
                return "from this Mac"
            },
            tools: { [log] _, _, _ in
                log.note("tools")
                return "from a tool"
            }
        )
        let endpoint = AIEndpoint(baseURL: "http://localhost:11434/v1", model: "small", apiKey: nil)
        for choice in [AIAnswer.Choice.api(endpoint), .appleIntelligence, .tools] {
            _ = try await AIAnswer.answer("why?", model: nil, choice: choice, localOnly: false, sources: sources) { _ in /* nothing streams */ }
        }
        #expect(log.onMain == ["api": false, "appleIntelligence": false, "tools": false])
    }

    @Test func aQuestionWithEarlierTurnsIsAnsweredOffTheMainThread() async throws {
        let sources = AISources(
            api: { [log] _, conversation, _ in
                // What each source makes of the turns is made here, with the request.
                log.note("api")
                return "\(conversation.earlierMessages.count)"
            },
            appleIntelligence: { [log] conversation, _ in
                log.note("appleIntelligence")
                return "\(AppleIntelligence.transcript(of: conversation).count)"
            },
            tools: { [log] conversation, _, _ in
                log.note("tools")
                return conversation.replayedPrompt
            }
        )
        let endpoint = AIEndpoint(baseURL: "http://localhost:11434/v1", model: "small", apiKey: nil)
        let conversation = AIConversation(earlier: [AIConversation.Turn(question: "why?", answer: "because")], question: "and then?")
        for choice in [AIAnswer.Choice.api(endpoint), .appleIntelligence, .tools] {
            _ = try await AIAnswer.answer(conversation, model: nil, choice: choice, localOnly: false, sources: sources) { _ in /* nothing streams */ }
        }
        #expect(log.onMain == ["api": false, "appleIntelligence": false, "tools": false])
    }

    @Test func aFollowUpIsAskedOffTheMainThread() async {
        let model = AskAIModel(
            question: "why?",
            source: nil,
            request: { [log] conversation, _ in
                log.note(conversation.earlier.isEmpty ? "first" : "follow-up")
                return "because"
            },
            pause: { /* no time passes between two updates */ }
        )
        await model.ask().value
        model.draft = "and then?"
        await model.askFollowUp()?.value
        #expect(model.turns.count == 1)
        #expect(log.onMain == ["first": false, "follow-up": false])
    }

    @Test func askAIAsksAndParsesOffTheMainThread() async {
        let model = AskAIModel(
            question: "why?",
            source: nil,
            request: { [log] _, emit in
                log.note("request")
                await emit("be")
                return "because"
            },
            parse: { [log] text, shown in
                log.note("parse")
                return MarkdownContent(text, reusing: shown)
            },
            pause: { /* no time passes between two updates */ }
        )
        await model.ask().value
        #expect(model.state == .finished)
        #expect(model.shown.text == "because")
        #expect(log.onMain == ["request": false, "parse": false])
    }

    @Test func theMarkdownOfAStreamingAnswerIsParsedOffTheMainActor() async {
        let stayed = await CountingExecutor.departures { _ = MarkdownContent("# Tides\n\nThe moon pulls.") }
        let left = await CountingExecutor.departures { _ = await MarkdownContent.parsed("# Tides\n\nThe moon pulls.", reusing: .empty) }
        #expect(stayed == 0, "parsing in place leaves nothing to count")
        #expect(left > 0)
    }

    // MARK: Documents and pictures

    @Test func theChangelogIsReadAndParsedOffTheMainActor() async {
        // With fetching off there is no request: the last copy, if any, is read from Caches and parsed.
        let left = await CountingExecutor.departures { _ = await ChangelogDocument.load(allowFetch: false) }
        #expect(left > 0)
    }

    @Test func theReleaseNotesAreLoadedOffTheMainThread() async {
        let view = WhatsNewView(load: { [log] in
            log.note("load")
            return (nil, .unavailable)
        })
        _ = await view.load()
        #expect(log.onMain == ["load": false])
    }

    @Test func anIconsThumbnailIsMadeOffTheMainActor() async {
        let cache = IconThumbnailCache(budget: 1024 * 1024) { [log] _ in
            log.note("render")
            return nil
        }
        let key = IconKey(source: .file(path: "/nowhere.png"), points: 16, scale: 2)
        let left = await CountingExecutor.departures { _ = await cache.load(key) }
        #expect(left > 0)
        #expect(log.onMain == ["render": false])
    }
}
