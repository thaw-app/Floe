//
//  ScriptActionsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing
import ThawUI
import UniformTypeIdentifiers

/// Script commands with a `@floe.subjects` line: how they are read, what they are told about the result, and where
/// the launcher offers them. No script is run.
@MainActor
struct ScriptActionsTests {
    private let app = AppEntry(name: "Floe Test App", url: URL(fileURLWithPath: "/System/Applications/NotARealApp-\(UUID().uuidString).app"))

    // MARK: - Reading the file

    private func parse(_ lines: String...) throws -> Result<ScriptCommand, ScriptParseError> {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-action-\(UUID().uuidString).sh")
        let text = (["#!/bin/sh", "# @raycast.schemaVersion 1", "# @raycast.title Upload"] + lines).joined(separator: "\n")
        try text.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        return ScriptCommand.parse(file: file)
    }

    @Test func aScriptNamesTheKindsItActsOn() throws {
        let script = try parse("# @floe.subjects app, file folder").get()
        #expect(script.subjects == [.app, .file, .folder])
        #expect(script.title == "Upload", "Raycast's lines read as before")
        #expect(try parse("# @floe.subjects link").get().subjects == [.url], "a link can be named either way")
    }

    @Test func aScriptWithoutTheLineIsSearchedFor() throws {
        #expect(try parse().get().subjects.isEmpty)
    }

    @Test func floeLinesAreNotRaycasts() throws {
        let script = try parse("# @floe.title Something else", "# @floe.mode silent").get()
        #expect(script.title == "Upload")
        #expect(script.mode == .fullOutput)
    }

    @Test func anUnknownKindIsRefused() throws {
        #expect(throws: ScriptParseError.unknownSubject("photo")) { try parse("# @floe.subjects app, photo").get() }
    }

    /// Left empty, the line would quietly leave the script in the search, with nothing in Settings to say why.
    @Test func aLineThatNamesNoKindIsRefused() throws {
        #expect(throws: ScriptParseError.noSubjects) { try parse("# @floe.subjects").get() }
        #expect(throws: ScriptParseError.noSubjects) { try parse("# @floe.subjects , ,").get() }
    }

    @Test func anActionCannotNeedAnArgument() throws {
        let required = #"# @raycast.argument1 {"type": "text", "placeholder": "Bucket"}"#
        #expect(throws: ScriptParseError.actionNeedsArgument(1)) { try parse("# @floe.subjects file", required).get() }
        #expect(try parse(required).get().arguments.count == 1, "a script searched for can still ask for one")
        let optional = #"# @raycast.argument1 {"type": "text", "placeholder": "Bucket", "optional": true}"#
        #expect(try parse("# @floe.subjects file", optional).get().arguments.count == 1)
    }

    // MARK: - What a script is told

    @Test func aFileIsToldWhereItIsAndWhatItIs() {
        let subject = ActionSubject(kind: .file, name: "Report.pdf", url: URL(fileURLWithPath: "/Users/me/Documents/Report.pdf"))
        let modified = Date(timeIntervalSince1970: 1_800_000_000)
        let facts = SubjectFacts(contentType: .pdf, size: 2048, modified: modified)
        let values = subject.environment(facts: facts, query: "report")

        #expect(values["FLOE_SUBJECT"] == "file")
        #expect(values["FLOE_NAME"] == "Report.pdf")
        #expect(values["FLOE_PATH"] == "/Users/me/Documents/Report.pdf")
        #expect(values["FLOE_URL"] == "file:///Users/me/Documents/Report.pdf")
        #expect(values["FLOE_FILENAME"] == "Report.pdf")
        #expect(values["FLOE_BASENAME"] == "Report")
        #expect(values["FLOE_EXTENSION"] == "pdf")
        #expect(values["FLOE_PARENT"] == "/Users/me/Documents")
        #expect(values["FLOE_CONTENT_TYPE"] == "com.adobe.pdf")
        #expect(values["FLOE_MIME_TYPE"] == "application/pdf")
        #expect(values["FLOE_TYPE_DESCRIPTION"] == UTType.pdf.localizedDescription)
        #expect(values["FLOE_SIZE"] == "2048")
        #expect(values["FLOE_MODIFIED"] == modified.formatted(.iso8601))
        #expect(values["FLOE_QUERY"] == "report")
        #expect(values["FLOE_CREATED"] == nil, "what Floe doesn't know is left unset")
        #expect(values["FLOE_BUNDLE_ID"] == nil && values["FLOE_APP_RUNNING"] == nil, "a file is no app")
        #expect(values["FLOE_HOST"] == nil)
    }

    @Test func anAppIsToldWhetherItRuns() {
        let subject = ActionSubject(kind: .app, name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))
        var facts = SubjectFacts(bundleIdentifier: "com.apple.Safari", version: "26.1", build: "21622")
        var values = subject.environment(facts: facts, query: "")
        #expect(values["FLOE_PATH"] == "/Applications/Safari.app")
        #expect(values["FLOE_BUNDLE_ID"] == "com.apple.Safari")
        #expect(values["FLOE_APP_VERSION"] == "26.1")
        #expect(values["FLOE_APP_BUILD"] == "21622")
        #expect(values["FLOE_APP_RUNNING"] == "0")
        #expect(values["FLOE_APP_PID"] == nil)
        #expect(values["FLOE_QUERY"] == "", "an empty search is still said")

        facts.process = SubjectFacts.AppProcess(pid: 412, isHidden: true)
        values = subject.environment(facts: facts, query: "")
        #expect(values["FLOE_APP_RUNNING"] == "1")
        #expect(values["FLOE_APP_PID"] == "412")
        #expect(values["FLOE_APP_HIDDEN"] == "1")
    }

    @Test func aLinkIsToldItsAddress() throws {
        let url = try #require(URL(string: "https://www.youtube.com/watch?v=abc"))
        let values = ActionSubject(kind: .url, name: "A Video", url: url).environment(facts: SubjectFacts(), query: "")
        #expect(values["FLOE_SUBJECT"] == "url")
        #expect(values["FLOE_URL"] == "https://www.youtube.com/watch?v=abc")
        #expect(values["FLOE_HOST"] == "www.youtube.com")
        #expect(values["FLOE_SCHEME"] == "https")
        #expect(values["FLOE_PATH"] == nil, "a link has no place on the disk")
    }

    @Test func aNameIsHandedOverAsItIs() {
        // Quotes, a dollar sign and a new line would change a command they were written into.
        let name = "it's \"$(rm -rf ~)\"\nnext"
        let subject = ActionSubject(kind: .folder, name: name, url: URL(fileURLWithPath: "/tmp/\(name)"))
        let values = subject.environment(facts: SubjectFacts(), query: "")
        #expect(values["FLOE_NAME"] == name)
        #expect(values["FLOE_FILENAME"] == name)
    }

    @Test func aFoldersPathEndsWithoutASlash() {
        let subject = ActionSubject(kind: .folder, name: "Documents", url: URL(fileURLWithPath: "/Users/me/Documents/", isDirectory: true))
        let values = subject.environment(facts: SubjectFacts(), query: "")
        #expect(values["FLOE_PATH"] == "/Users/me/Documents")
        #expect(values["FLOE_PARENT"] == "/Users/me")
        let root = ActionSubject(kind: .folder, name: "Macintosh HD", url: URL(fileURLWithPath: "/", isDirectory: true))
        let told = root.environment(facts: SubjectFacts(), query: "")
        #expect(told["FLOE_PATH"] == "/")
        #expect(told["FLOE_PARENT"] == nil, "the startup disk has no parent")
        #expect(told["FLOE_FILENAME"] == nil)
        #expect(told["FLOE_NAME"] == "Macintosh HD")
    }

    @Test func aFilesFactsAreReadFromTheDisk() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-facts-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let facts = await SubjectFacts.read(ActionSubject(kind: .file, name: file.lastPathComponent, url: file))
        #expect(facts.size == 5)
        #expect(facts.contentType == .plainText)
        #expect(facts.modified != nil)
        #expect(facts.bundleIdentifier == nil)
        let folder = await SubjectFacts.read(ActionSubject(kind: .folder, name: "tmp", url: file.deletingLastPathComponent()))
        #expect(folder.size == nil, "a folder's size would mean adding up all it holds")
    }

    /// A symbolic link's kind is that of what it points at, and so are the facts a script is told.
    @Test func aLinkedFileIsReadThroughItsLink() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-target-\(UUID().uuidString).txt")
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("floe-link-\(UUID().uuidString).txt")
        try Data("hello there".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: file)
        }
        let facts = await SubjectFacts.read(ActionSubject(kind: .file, name: link.lastPathComponent, url: link))
        #expect(facts.size == 11)
        #expect(facts.contentType == .plainText)
    }

    /// A hotkey left on a script that now acts on results runs nothing, and would keep its keys from every row.
    @Test func hotkeysLeftOnActionScriptsAreTakenOff() {
        let settings = AppSettings(defaults: MemoryDefaults())
        let action = script("Upload", file: "upload.sh", on: [.file])
        let searched = script("Deploy", file: "deploy.sh", on: [])
        let left = KeyCombination(key: .j, modifiers: [.command, .shift])
        let kept = KeyCombination(key: .l, modifiers: [.command, .shift])
        settings.commandHotkeys = [action.id: left, searched.id: kept]
        settings.dropHotkeys(of: [action])
        #expect(settings.commandHotkeys == [searched.id: kept])
        #expect(!settings.floeHotkeys.contains(left), "so a row can have the keys again")
    }

    // MARK: - Where the launcher offers it

    private func script(_ title: String, file: String, on kinds: Set<SubjectKind>) -> ScriptCommand {
        ScriptCommand(
            file: URL(fileURLWithPath: "/tmp/\(file)"), title: title, packageName: nil, mode: .silent,
            needsConfirmation: false, icon: nil, arguments: [], subjects: kinds
        )
    }

    private func makeModel(scripts: [ScriptCommand], choices: KindActions? = nil) -> LauncherModel {
        let settings = AppSettings(defaults: MemoryDefaults())
        if let choices {
            settings.actionChoices = [SubjectKind.app.rawValue: choices]
        }
        return LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [app], commands: [], scripts: scripts))
    }

    @Test func aScriptIsListedAfterFloesRowsOnTheKindsItActsOn() throws {
        let upload = script("Upload", file: "upload.sh", on: [.app])
        let model = makeModel(scripts: [upload, script("Shorten", file: "shorten.sh", on: [.url])])
        let rows = model.rootActions(for: .app(app))
        #expect(rows.last??.title == "Upload")
        #expect(rows.last??.id == upload.actionID)
        #expect(rows[rows.count - 2] == nil, "a separator parts the user's rows from Floe's")
        #expect(!rows.contains { $0?.title == "Shorten" }, "a script on links is not offered on an app")
        let address = try #require(URL(string: "https://example.com"))
        #expect(model.rootActions(for: .bookmark(WebBookmark(title: "Example", url: address, browser: "Safari"))).contains { $0?.title == "Shorten" })
        #expect(!model.rootActions(for: .system(.toggleMute)).contains { $0?.title == "Upload" }, "a result with no kind has none")
    }

    @Test func aScriptChosenForReturnRunsOnTheResult() {
        let upload = script("Upload", file: "upload.sh", on: [.app])
        var choices = KindActions()
        choices.defaults = [upload.actionID]
        let model = makeModel(scripts: [upload], choices: choices)
        var ran: [(String, ActionSubject)] = []
        model.features.actions.host.runScript = { ran.append(($0.title, $1)) }
        let item = RootItem.app(app)

        #expect(model.primaryActionTitle(for: item) == "Upload")
        model.activate(item)
        #expect(ran.map(\.0) == ["Upload"])
        #expect(ran.first?.1 == ActionSubject(kind: .app, name: app.name, url: app.url))
    }

    @Test func aScriptsKeysRunIt() throws {
        let upload = script("Upload", file: "upload.sh", on: [.app])
        var choices = KindActions()
        choices.shortcuts = [upload.actionID: KeyCombination(key: .o, modifiers: [.command, .option])]
        let model = makeModel(scripts: [upload], choices: choices)
        var ran: [String] = []
        model.features.actions.host.runScript = { script, _ in ran.append(script.title) }
        model.settings.launcherLayout = .extended
        model.query = app.name
        model.refresh()
        model.selection = try #require(model.results.firstIndex { $0.item.id == RootItem.app(app).id })

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 31
        ))
        #expect(try model.handlePanelKey(event, layout: .extended))
        #expect(ran == ["Upload"])
        #expect(model.rootActions(for: .app(app)).last??.shortcut == KeyCombination(key: .o, modifiers: [.command, .option]), "the menu shows its keys")
    }

    /// File Search has a field of its own: a script run there is told what is typed in it.
    @Test func aScriptIsToldTheSearchOnScreen() async throws {
        let upload = script("Upload", file: "upload.sh", on: [.file])
        let model = makeModel(scripts: [upload])
        let told = Told()
        model.features.scripts.runScript = { _, _, environment in
            told.environment = environment
            return ShellResult(status: 0, stdout: Data(), stderr: Data())
        }
        // A file's kind is read from the disk, so it is there.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floe-invoice-\(UUID().uuidString).pdf")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.query = "search files"
        model.openFileSearch(with: "invoice")
        let file = FileResult(url: url, name: url.lastPathComponent, displayPath: "", contentType: nil, lastUsed: nil)
        let row = try #require(model.fileSearch.actions(for: file).compactMap(\.self).first { $0.id == upload.actionID })
        row.run()
        for _ in 0 ..< 200 where told.environment == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(told.environment?["FLOE_QUERY"] == "invoice")
        #expect(told.environment?["FLOE_FILENAME"] == url.lastPathComponent)
    }

    /// Choices stay with a script's file name, so a renamed script leaves its keys behind. They must not keep the
    /// same keys from the script under its new name, in Settings or in the launcher.
    @Test func keysLeftOnARenamedScriptGoToNoRow() {
        let renamed = script("Upload", file: "upload2.sh", on: [.app])
        let keys = KeyCombination(key: .o, modifiers: [.command, .option])
        var choices = KindActions()
        choices.shortcuts = [ActionID(rawValue: "script:upload.sh"): keys]
        let rows = ActionOption.rows(for: .app, roleApps: [], scripts: [renamed])
        #expect(choices.setKeys(keys, for: renamed.actionID, of: .app, among: rows) == nil)
        #expect(choices.keys(for: renamed.actionID, of: .app, among: rows) == keys)

        let model = makeModel(scripts: [renamed], choices: choices)
        #expect(model.rootActions(for: .app(app)).last??.shortcut == keys, "the old name sorts first, and still has none")
    }

    @Test func aScriptThatActsOnResultsIsNotSearchedFor() {
        let model = makeModel(scripts: [script("Upload Thing", file: "upload.sh", on: [.file]), script("Deploy Thing", file: "deploy.sh", on: [])])
        model.query = "Thing"
        model.refresh()
        let found = model.results.compactMap { result -> String? in
            guard case let .script(script) = result.item else { return nil }
            return script.title
        }
        #expect(found == ["Deploy Thing"])
    }

    @Test func settingsListsTheScriptsOfAKind() {
        let scripts = [script("Upload", file: "upload.sh", on: [.app, .file]), script("Shorten", file: "shorten.sh", on: [.url])]
        let rows = ActionOption.rows(for: .app, roleApps: [], scripts: scripts)
        #expect(rows.last == ActionOption(id: scripts[0].actionID, title: "Upload"))
        #expect(!rows.contains { $0.title == "Shorten" })
        #expect(ActionOption.rows(for: .url, roleApps: [], scripts: scripts).last?.title == "Shorten")
        #expect(scripts[0].actsOnLabel == "Actions on Apps and Files")
    }

    /// Return on a file, through the launcher as it is wired, runs a real script that writes down what it was told.
    @Test func returnRunsAChosenScriptOnAFileForReal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-action-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let report = folder.appendingPathComponent("told.txt")
        let script = folder.appendingPathComponent("tell.sh")
        try """
        #!/bin/sh
        # @raycast.schemaVersion 1
        # @raycast.title Tell
        # @raycast.mode silent
        # @floe.subjects file
        printf '%s\\n' "$FLOE_SUBJECT" "$FLOE_NAME" "$FLOE_PARENT" "$FLOE_EXTENSION" "$FLOE_SIZE" "$FLOE_CONTENT_TYPE" "$FLOE_QUERY" > '\(report.path)'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let file = folder.appendingPathComponent("notes.txt")
        try Data("twelve bytes".utf8).write(to: file)

        let command = try ScriptCommand.parse(file: script).get()
        let settings = AppSettings(defaults: MemoryDefaults())
        var choices = KindActions()
        choices.defaults = [command.actionID]
        settings.actionChoices = [SubjectKind.file.rawValue: choices]
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [], scripts: [command]))
        model.query = "notes"
        let item = RootItem.file(FileResult(url: file, name: "notes.txt", displayPath: folder.path, contentType: nil, lastUsed: nil))

        #expect(model.primaryActionTitle(for: item) == "Tell")
        model.activate(item)
        for _ in 0 ..< 200 where !FileManager.default.fileExists(atPath: report.path) {
            try await Task.sleep(for: .milliseconds(25))
        }
        let told = try String(contentsOf: report, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let parent = folder.standardizedFileURL.path(percentEncoded: false).replacing(/\/$/, with: "")
        #expect(told.prefix(7) == ["file", "notes.txt", parent, "txt", "12", "public.plain-text", "notes"])
    }
}

/// What a script was told, set from the runner off the main actor.
private final nonisolated class Told: @unchecked Sendable {
    var environment: [String: String]?
}
