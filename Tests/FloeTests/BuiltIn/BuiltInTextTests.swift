//
//  BuiltInTextTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices
@testable import Floe
import Foundation
import Testing

/// The sentences the built-ins and the AI sources write around a value: the English they had before they
/// could be translated, and a name taken as it is written, whatever it holds.
@MainActor
struct BuiltInTextTests {
    /// What a format string would read as a placeholder, and what Swift would read as an interpolation.
    private static let awkward = #"50% off %@ \(x) %1$@ %lld"#

    // MARK: System commands

    @Test func everySystemCommandKeepsItsEnglishTitle() {
        #expect(SystemCommand.allCases.map(\.title) == [
            "Lock Screen", "Sleep", "Sleep Displays", "Restart", "Shut Down", "Log Out", "Empty Trash", "Toggle Dark Mode",
            "Toggle Wi-Fi", "Toggle Mute", "Toggle Keep Awake", "Hide Other Apps", "Quit All Apps",
        ])
    }

    @Test(arguments: SystemCommand.allCases)
    func aSystemCommandIsFoundByItsTitle(command: SystemCommand) {
        let results = Ranking.search(
            SystemCommand.allCases.map(RootItem.system), query: command.title, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }
        )
        #expect(results.first?.item.id == "system:\(command.rawValue)")
    }

    @Test func theWordsThatFindACommandAreTheOnesTheyWere() {
        #expect(SystemCommand.lockScreen.keywords == ["lock", "screen"])
        #expect(SystemCommand.sleepDisplays.keywords == ["sleep", "displays", "screen off", "monitor"])
        #expect(SystemCommand.toggleWiFi.keywords == ["wifi", "wireless", "airport", "turn wi-fi off", "turn wi-fi on"])
        #expect(SystemCommand.quitAllApps.keywords == ["quit all apps", "quit all", "close all apps"])
        #expect(ThawAction.toggleHidden.keywords == ["thaw", "menu bar", "hidden", "show hidden"])
        #expect(ThawAction.toggleHideApplicationMenus.keywords == ["thaw", "hide menus"])
        #expect(SystemSettingsPane.known["com.apple.Displays-Settings.extension"]?.keywords == ["monitor", "screen", "resolution", "night shift", "brightness"])
        #expect(SystemSettingsPane.known["com.apple.Lock-Screen-Settings.extension"]?.title == "Lock Screen")
        #expect(SystemSettingsPane.known["com.apple.settings.PrivacySecurity.extension"]?.title == "Privacy & Security")
        #expect(SystemSettingsPane.known["com.apple.wifi-settings-extension"]?.title == "Wi-Fi")
        #expect(SystemSettingsPane.known["com.apple.Spotlight-Settings.extension"]?.keywords == [])
    }

    @Test func aListOfWordsIsSplitAtItsCommas() {
        #expect("lock, screen".keywordList == ["lock", "screen"])
        #expect(" screen off ,monitor,, ".keywordList == ["screen off", "monitor"])
        #expect("".keywordList.isEmpty)
    }

    @Test func theAgendaStillAnswersToItsWords() {
        for word in ["calendar", "today", "meetings", "events", "agenda", "next meeting"] {
            #expect(CalendarAgenda.isTrigger(word), "\(word)")
        }
        #expect(!CalendarAgenda.isTrigger("restart"))
    }

    @Test func anEmojiIsStillFoundByItsExtraWords() {
        let flame = EmojiCatalog.search(term: "flame", frecency: { _ in 0 })
        #expect(flame.first?.character == "🔥")
        #expect(EmojiCatalog.entries().first { $0.character == "👍" }?.keywords == ["thumbs up", "thumbsup", "like", "approve", "yes"])
    }

    // MARK: SSH

    @Test func aHostNameIsCopiedAndNamedAsItIsWritten() {
        var copied: [String] = []
        var said: [String] = []
        let host = SSHHost(alias: Self.awkward, hostName: nil, user: nil)
        let actions = SSHHostActions.actions(for: host, host: ActionHost(showHUD: { said.append($0) }, dismiss: {}), copy: { copied.append($0) })
        #expect(actions.compactMap { $0?.title } == ["Copy Host Name", "Copy SSH Command"])
        for action in actions {
            action?.run()
        }
        #expect(copied == [Self.awkward, SSHConnection.command(for: Self.awkward)])
        #expect(said == ["Copied \(Self.awkward)", "Copied \(SSHConnection.command(for: Self.awkward))"])
    }

    @Test func theLinesAboutATerminalNameIt() {
        let connector = SSHConnector(
            bundleIdentifier: { $0.lastPathComponent == "Terminal.app" ? AppRole.systemTerminal : "com.example.other" },
            takesSSHLinks: { _ in false },
            systemTerminal: { URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app") },
            open: { _ in },
            runScript: { _ in .failed }
        )
        let other = ResolvedApp(url: URL(fileURLWithPath: "/Applications/Other.app"))
        let plan = SSHConnection.plan(alias: "build-box", terminal: other, using: connector)
        #expect(plan.notice == "\(other.name) takes no command from Floe, so the connection opened in \(plan.app)")
        #expect(SSHConnection.unsafeAliasNotice == "Not connected. Floe only passes on host names made of letters, digits, dots, hyphens and underscores.")
        #expect(SSHConnection.noTerminalNotice == "Not connected. Choose a terminal in Floe Settings.")
    }

    @Test func aTerminalThatFailsIsNamed() async {
        let connector = SSHConnector(
            bundleIdentifier: { _ in nil }, takesSSHLinks: { _ in false }, systemTerminal: { nil }, open: { _ in }, runScript: { _ in .failed }
        )
        let outcome = await SSHConnection.open(SSHConnectionPlan(step: .script("return 1"), app: Self.awkward), using: connector)
        #expect(outcome == .finished("Couldn't open the connection in \(Self.awkward)"))
    }

    // MARK: Shortcuts

    @Test func aShortcutThatFailsIsNamedAsItIsWritten() async {
        let shortcut = AppleShortcut(name: Self.awkward, identifier: "0C9A4E0B-2B0F-4B55-9C3F-0D1B5A6E7F01")
        let silent = ShortcutsTool { _ in ShortcutsToolResult(succeeded: false) }
        #expect(await silent.run(shortcut) == "\(Self.awkward) failed. Open it in Shortcuts to see why.")
        #expect(await silent.view(shortcut) == "Couldn't open \(Self.awkward) in Shortcuts. Open the Shortcuts app and look for it there.")

        let reason = "100% of %@ went wrong"
        let loud = ShortcutsTool { _ in ShortcutsToolResult(succeeded: false, errorOutput: "first line\n\(reason)\n") }
        #expect(await loud.run(shortcut) == "\(Self.awkward) failed: \(reason)")
        #expect(await loud.view(shortcut) == "Couldn't open \(Self.awkward) in Shortcuts: \(reason)")
    }

    @Test func aPlainShortcutNameReadsAsItDid() async {
        let shortcut = AppleShortcut(name: "Resize Image (Half)", identifier: "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D")
        let tool = ShortcutsTool { _ in ShortcutsToolResult(succeeded: false, errorOutput: "Error: no input") }
        #expect(await tool.run(shortcut) == "Resize Image (Half) failed: Error: no input")
        #expect(await tool.view(shortcut) == "Couldn't open Resize Image (Half) in Shortcuts: Error: no input")
    }

    // MARK: Calendar, calculator, clipboard

    @Test func anEventSaysWhenAndInWhichCalendar() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3600)
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        func event(allDay: Bool) -> CalendarEvent {
            CalendarEvent(identifier: "1", title: "Review", startDate: start, endDate: end, isAllDay: allDay, calendarTitle: Self.awkward, meetingURL: nil)
        }
        #expect(event(allDay: true).subtitle == "All day · \(Self.awkward)")
        #expect(event(allDay: false).subtitle == "\(start.formatted(time)) to \(end.formatted(time)) · \(Self.awkward)")
    }


    @Test func severalCopiedFilesAreCounted() {
        func entry(_ paths: [String]) -> ClipboardEntry {
            ClipboardEntry(id: UUID(), kind: .file, filePaths: paths, date: Date(), pinned: false)
        }
        #expect(entry(["/tmp/a.txt", "/tmp/b.txt"]).title == "2 files")
        #expect(entry([]).title == "0 files")
        #expect(entry(["/tmp/only.txt"]).title == "only.txt")
        #expect(ClipboardEntry(id: UUID(), kind: .image, date: Date(), pinned: false).title == "Image")
    }

    // MARK: Menu bar, tabs, scripts, selection

    @Test func theActionsOfAMenuBarItemNameItsApp() throws {
        let scratch = try #require(UserDefaults(suiteName: "floe-built-in-text-tests-\(UUID().uuidString)"))
        let model = MenuBarSearchModel(settings: AppSettings(defaults: scratch), recents: MenuBarSearchRecents(defaults: scratch))
        let extra = MenuBarExtra(
            id: "1", name: "Clock", ownerName: Self.awkward, ownerURL: URL(fileURLWithPath: "/Applications/Example.app"),
            frame: .zero, element: AXUIElementCreateSystemWide()
        )
        #expect(model.actions(for: extra).compactMap { $0?.title } == [
            "Click Item", "Edit Name", "Copy Name", "Open \(Self.awkward)", "Show \(Self.awkward) in Finder",
        ])
    }

    @Test func aBrowserThatMayNotBeAskedIsNamed() {
        #expect(BrowserTabRow.access(.safari).title == "Floe needs permission to list Safari's tabs")
    }

    @Test func aScriptThatDoesNotParseSaysWhy() {
        #expect(ScriptParseError.unsupportedSchemaVersion("2%@").errorDescription == "Unsupported @raycast.schemaVersion 2%@. Floe reads version 1.")
        #expect(ScriptParseError.unsupportedMode("loud").errorDescription == "Unknown @raycast.mode loud. Use fullOutput, compact, silent or inline.")
        #expect(ScriptParseError.invalidArgument(2).errorDescription
            == #"@raycast.argument2 isn't valid JSON with a placeholder, e.g. {"type": "text", "placeholder": "Name"}."#)
        #expect(ScriptParseError.missingSchemaVersion.errorDescription == "Missing @raycast.schemaVersion. Add `# @raycast.schemaVersion 1`.")
    }

    @Test func theSelectionErrorsReadAsTheyDid() {
        #expect(SelectionError.accessibilityOff.errorDescription
            == "Getting the selected text needs Accessibility access. Turn it on under System Settings › Privacy & Security › Accessibility.")
        #expect(SelectionError.noSelectedText.errorDescription == "Unable to get selected text from frontmost application")
        #expect(SelectionError.finderAutomation(Self.awkward).errorDescription == Self.awkward)
    }

    // MARK: AI

    @Test func theLinesAboutACommandLineToolNameIt() {
        #expect(AIToolOption.options(chosen: .pi, which: { _ in nil }).map(\.title) == ["Automatic", "pi (not installed)"])
        #expect(AIToolOption.problem(chosen: nil) == "AI can't answer yet. Install claude, codex, opencode or pi and sign in.")
        #expect(AIToolOption.problem(chosen: .codex) == "AI can't answer yet. codex is not installed. Install it and sign in, or choose another tool.")
        #expect(AIEngine.missingMessage(for: AIEngine.Setup(tool: .opencode))
            == "AI is set to answer with opencode, which is not installed. Install it and sign in, or choose another tool under Settings › General › AI.")
        #expect(AskAI.source(for: .tools, tool: Self.awkward)?.line == "The \(Self.awkward) tool, on your account")
    }

    @Test func aFailedCommandOrRequestSaysItsNumber() async {
        #expect(ShellResult(status: 2, stdout: Data(), stderr: Data()).failureMessage == "The command failed with exit code 2.")
        #expect(ChatCompletionStream.errorMessage(fromBody: " ", statusCode: 503) == "The API returned status 503.")
        await #expect(throws: ShellError.self) {
            try await Shell.run(tool: "floe-no-such-tool-\(UUID().uuidString)", [])
        }
        do {
            _ = try await Shell.run(tool: "floe-no-such-tool", [])
        } catch {
            #expect(error.localizedDescription == "floe-no-such-tool was not found on your PATH.")
        }
    }

    @Test func aConnectionThatKeepsDroppingSaysHowOftenItWasTried() {
        struct Silent: LocalizedError {
            var errorDescription: String? {
                ""
            }
        }
        struct Loud: LocalizedError {
            var errorDescription: String? {
                "50% of %@ packets lost"
            }
        }
        #expect(ChatCompletionStream.terminalTransportMessage(Silent(), attempts: 3)
            == "The API could not be reached after 3 attempts. Check the connection, then try again.")
        #expect(ChatCompletionStream.terminalTransportMessage(Loud(), attempts: 4)
            == "The API could not be reached after 4 attempts. Check the connection, then try again. (50% of %@ packets lost)")
    }
}
