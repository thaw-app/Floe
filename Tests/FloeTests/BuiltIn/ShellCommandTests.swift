//
//  ShellCommandTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// What the stand-in runner was asked to run, which it is told off the main actor.
private final nonisolated class Commands: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [String] = []

    func add(_ command: String) {
        lock.withLock { commands.append(command) }
    }

    var all: [String] {
        lock.withLock { commands }
    }
}

@MainActor
struct ShellCommandTests {
    @Test(arguments: [
        ("> pkill -f debug/ThawNotch", CommandPrefix.greaterThan, "pkill -f debug/ThawNotch"),
        (">ls", .greaterThan, "ls"),
        ("$ echo hi", .dollar, "echo hi"),
        ("! say done ", .exclamation, "say done"),
    ])
    func thePrefixMakesTheRestACommand(query: String, prefix: CommandPrefix, command: String) {
        #expect(ShellCommand.command(in: query, prefix: prefix) == command)
    }

    @Test(arguments: [
        ("pkill -f debug/ThawNotch", CommandPrefix?.some(.greaterThan)), (">", .some(.greaterThan)), (">   ", .some(.greaterThan)),
        ("$ echo hi", .some(.greaterThan)), (" > ls", .some(.greaterThan)), ("> ls", .none),
    ])
    func withoutThePrefixOrACommandItIsAnOrdinarySearch(query: String, prefix: CommandPrefix?) {
        #expect(ShellCommand.command(in: query, prefix: prefix) == nil)
    }

    @Test func shellSettingsFromBeforeASwitchExistedReadAsItsDefault() throws {
        let old = try JSONDecoder().decode(ShellSettings.self, from: Data(#"{"prefix":"$","runs":false}"#.utf8))
        #expect(old.prefix == .dollar)
        #expect(!old.runs)
        #expect(old.recognizes && old.suggests, "what the file does not say is on, as in a new install")
        #expect(try JSONDecoder().decode(ShellSettings.self, from: Data("{}".utf8)) == ShellSettings())
        let written = try JSONEncoder().encode(ShellSettings.off)
        #expect(try JSONDecoder().decode(ShellSettings.self, from: written) == .off)

        let defaults = try #require(UserDefaults(suiteName: "floe-shell-settings-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        settings.shell.prefix = .exclamation
        settings.shell.suggests = false
        settings.save()
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.shell.prefix == .exclamation)
        #expect(!reloaded.shell.suggests)
        #expect(reloaded.shell.runs)
    }

    @Test func whatReturnDoesIsOneAnswerForEveryRowOfTheShell() {
        let typed = RootItem.shell(ShellRow(text: "ls", origin: .typed), terminal: nil)
        let earlier = RootItem.shell(ShellRow(text: "git pull", origin: .history), terminal: nil)
        let unfinished = RootItem.shell(ShellRow(text: "git ", origin: .completion), terminal: nil)
        #expect([typed, earlier, unfinished, RootItem.settings].map { $0.shellAction?.title } == ["Run", "Run", "Complete", nil])
        #expect([typed, earlier, unfinished].map(\.kind) == ["Shell", "History", "Complete"])
        #expect([typed, earlier, unfinished].map(\.id) == ["shell-command", "shell-suggestion:history:git pull", "shell-suggestion:completion:git "])
        #expect([typed, earlier, unfinished].map(\.isScopeResult) == [true, true, true])
    }

    @Test func onlySudoIsSentToATerminalUnasked() {
        #expect(ShellCommand.needsATerminal("sudo purge"))
        #expect(!ShellCommand.needsATerminal("pkill -f sudo"))
        #expect(!ShellCommand.needsATerminal("sudoku"))
    }

    @Test func aFinishedCommandComesDownToOneLine() {
        #expect(ShellCommand.summary(status: 0, output: "\n  first\nsecond\n", errors: "") == "first")
        #expect(ShellCommand.summary(status: 0, output: "", errors: "a warning") == "Done")
        #expect(ShellCommand.summary(status: 1, output: "", errors: "no such process\nmore") == "no such process (code 1)")
        #expect(ShellCommand.summary(status: 2, output: "said on output", errors: "") == "said on output (code 2)")
        #expect(ShellCommand.summary(status: 3, output: "", errors: " \n") == "The command ended with code 3.")
    }

    @Test func aCommandRunsInTheLoginShellFromTheHomeFolder() async {
        #expect(await ShellCommand.run("pwd && echo second") == FileManager.default.homeDirectoryForCurrentUser.path)
        let failed = await ShellCommand.finished("echo printed; echo nope >&2; exit 7")
        #expect(failed.line == "nope (code 7)")
        #expect(failed.output == "printed\n\nnope\n\nThe command ended with code 7.")
    }

    @Test func scriptsHandedToATerminalAreClearedOutADayLater() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["old.command", "new.command", "old.txt"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        for name in ["old.command", "old.txt"] {
            try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: folder.appendingPathComponent(name).path)
        }
        ShellCommand.removeScripts(in: folder, olderThan: Date().addingTimeInterval(-24 * 60 * 60))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["new.command", "old.txt"], "only Floe's own scripts, and only the old ones")
        #expect(ShellCommand.examples(for: "tar") == "tldr tar")
    }

    @Test func theScriptForATerminalRunsTheCommandAndLeavesAShellOpen() {
        #expect(ShellCommand.script(for: "top -o cpu", shell: "/bin/zsh") == "#!/bin/zsh -l\ncd ~\ntop -o cpu\nexec /bin/zsh -l\n")
    }

    @Test(arguments: [
        "pkill -f debug/ThawNotch", "open -a Safari", "ls ~/Downloads", "ps aux | grep Floe", "git log --oneline", "cat notes.txt > out.txt", "python3 ./run.py",
    ])
    func aProgramWithTheGrammarOfACommandLineReadsAsACommand(query: String) {
        #expect(ShellCommand.reads(asACommand: query) { _ in true })
    }

    @Test(arguments: [
        "find my keys", "git status", "pkill", "top -5", "Open -a Safari", "5 - 3", "what is -f", "2/3 of 9", "a/b testing notes",
    ])
    func aSentenceOrABareProgramDoesNot(query: String) {
        #expect(!ShellCommand.reads(asACommand: query) { name in name != "what" && name != "a" && name != "2/3" })
    }

    @Test func aWordThatIsNoProgramOnThisMacIsNeverACommand() {
        #expect(!ShellCommand.reads(asACommand: "floe-no-such-tool -f x") { _ in false })
        #expect(ShellCommand.isProgram("ls"))
        #expect(!ShellCommand.isProgram("floe-no-such-tool-\(UUID().uuidString)"))
    }

    @Test func aRecognizedCommandSitsUnderTheOtherResultsAndOnlyWhenAskedFor() {
        var provider = ShellCommandSearchProvider()
        provider.isProgram = { $0 == "pkill" }
        var recognizing = SearchContext(query: "pkill -f debug/ThawNotch")
        recognizing.shell.runs = true
        recognizing.shell.recognizes = true
        let found = provider.contribution(for: recognizing)
        #expect(found.pinned.isEmpty, "a guess never leads the results")
        #expect(found.appended.map(\.item.title) == ["Run pkill -f debug/ThawNotch"])
        #expect(provider.contribution(for: SearchContext(query: "pkill -f debug/ThawNotch")).appended.isEmpty)
        var sentence = SearchContext(query: "find my keys")
        sentence.shell.runs = true
        sentence.shell.recognizes = true
        #expect(provider.contribution(for: sentence).appended.isEmpty)
    }

    @Test func aSavedCommandIsAScriptCommandTheSearchFindsByItsName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-saved-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try ShellCommand.save("pkill -f debug/ThawNotch", as: "Kill ThawNotch: debug", in: folder)
        #expect(file.lastPathComponent == "kill-thawnotch-debug.sh")
        #expect(FileManager.default.isExecutableFile(atPath: file.path))
        let script = try ScriptCommand.parse(file: file).get()
        #expect(script.title == "Kill ThawNotch: debug")
        #expect(script.mode == .silent)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("\npkill -f debug/ThawNotch\n"))

        let again = try ShellCommand.save("echo second", as: "Kill ThawNotch: debug", in: folder)
        #expect(again.lastPathComponent == "kill-thawnotch-debug-2.sh", "a name already taken is numbered, never overwritten")
        #expect(ShellCommand.fileName(for: "¡¡¡", taken: []) == "command.sh")
    }

    @Test func aSavedCommandRuns() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-saved-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        // The plain shell, so the test does not read this Mac's own shell setup.
        let file = try ShellCommand.save("echo saved and run", as: "Say it", in: folder, shell: "/bin/sh")
        let result = try await ScriptRunner.run(ScriptCommand.parse(file: file).get(), arguments: [])
        #expect(result.succeeded)
        #expect(ScriptRunner.lastLine(result.output) == "saved and run")
    }

    private func context(_ query: String, prefix: CommandPrefix?) -> SearchContext {
        var context = SearchContext(query: query)
        if let prefix {
            context.shell.runs = true
            context.shell.prefix = prefix
        }
        return context
    }

    @Test func aManualIsReadAsPlainTextAndColoursAreTakenOut() {
        #expect(ShellCommand.asReading("man rsync") == "MANWIDTH=90 man -P cat rsync 2>&1 | col -bx")
        #expect(ShellCommand.asReading("man 5 crontab") == "MANWIDTH=90 man -P cat 5 crontab 2>&1 | col -bx")
        #expect(ShellCommand.asReading("man") == nil)
        #expect(ShellCommand.asReading("man ls | grep color") == nil, "a pipeline of the user's own is left as typed")
        #expect(ShellCommand.asReading("manual") == nil)
        #expect(ShellCommand.program(of: "pkill -f x") == "pkill")
        #expect(ShellCommand.program(of: "sudo purge") == "purge")
        #expect(ShellCommand.program(of: "") == nil)
        #expect(ShellCommand.plain("\u{1B}[1;32mgreen\u{1B}[0m and plain") == "green and plain")
    }

    @Test func theManualOfAProgramComesBackAsReadableText() async {
        let manual = await ShellCommand.finished(ShellCommand.manual(for: "ls"))
        #expect(manual.output.contains("list directory contents"))
        #expect(!manual.output.contains("\u{8}"), "no letters typed twice for bold")
    }

    @Test func aCommandRunsInTheFolderItIsGiven() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-folder-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The shell may name the folder through /private, so the end of the path is what is compared.
        #expect(await ShellCommand.finished("pwd", in: folder).line.hasSuffix("/" + folder.lastPathComponent))
    }

    @Test func theWholeOutputIsWhatWasPrintedThenWhatWasSaidInError() {
        #expect(ShellCommand.transcript(status: 0, output: "one\ntwo\n", errors: "") == "one\ntwo")
        #expect(ShellCommand.transcript(status: 0, output: "", errors: "") == "Done")
        #expect(ShellCommand.transcript(status: 0, output: "out\n", errors: "warned\n") == "out\n\nwarned")
    }

    /// A provider that reads nothing of this Mac: the given history and programs, and one folder.
    private func provider(history: [String] = [], programs: [String] = []) -> ShellCommandSearchProvider {
        var provider = ShellCommandSearchProvider()
        provider.history = { history }
        provider.programs = { programs }
        provider.entries = { $0 == "~/" ? ["Desktop/", "Documents/", "notes.txt"] : [] }
        return provider
    }

    @Test func earlierCommandsProgramsAndPathsAreOfferedUnderTheCommand() {
        var typing = context("> gi", prefix: .greaterThan)
        typing.shell.suggests = true
        let rows = provider(history: ["git pull", "ls", "git status"], programs: ["gist", "git", "grep"]).contribution(for: typing).pinned.map(\.item)
        #expect(rows.map(\.title) == ["Run gi", "git pull", "git status", "gist ", "git "])
        #expect(rows.map(\.kind) == ["Shell", "History", "History", "Complete", "Complete"])
        #expect(Set(rows.map(\.id)).count == rows.count, "each row is its own")

        var path = context("> open ~/D", prefix: .greaterThan)
        path.shell.suggests = true
        #expect(provider().contribution(for: path).pinned.map(\.item.title) == ["Run open ~/D", "open ~/Desktop/", "open ~/Documents/"])

        var bare = context(">", prefix: .greaterThan)
        bare.shell.suggests = true
        #expect(provider(history: ["git pull", "ls"]).contribution(for: bare).pinned.map(\.item.title) == ["git pull", "ls"], "the prefix alone lists the newest commands")

        #expect(provider(history: ["git pull"]).contribution(for: context("> gi", prefix: .greaterThan)).pinned.map(\.item.title) == ["Run gi"], "switched off, only the typed command")
    }

    @Test func theProviderLeadsWithTheRowAndStaysOutWhenSwitchedOff() {
        let found = ShellCommandSearchProvider().contribution(for: context("> uptime", prefix: .greaterThan))
        #expect(found.pinned.map(\.item.title) == ["Run uptime"])
        #expect(found.pinned.first?.item.id == "shell-command", "the command is not in the id, so nothing keeps it by that")
        #expect(found.pinned.first?.item.kind == "Shell")
        #expect(ShellCommandSearchProvider().contribution(for: context("> uptime", prefix: nil)).pinned.isEmpty)
        #expect(ShellCommandSearchProvider().contribution(for: context("uptime", prefix: .greaterThan)).pinned.isEmpty)
    }

    @Test func returnRunsItSaysWhatItPrintedAndRemembersTheSearch() async throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-shell-tests-\(UUID().uuidString)"))
        let usage = UsageStore(defaults: defaults)
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: usage, snapshot: CatalogSnapshot(apps: [], commands: []))
        let ran = Commands()
        model.shell.hasProgram = { _ in false }
        model.shell.run = { command, folder in
            ran.add(folder.map { "\(command) in \($0.path)" } ?? command)
            return ("ok", "ok\nand the rest")
        }
        var shown: [String] = []
        model.shell.showOutput = { title, output in shown.append("\(title): \(output)") }
        var said: [String] = []
        model.showHUD = { said.append($0) }

        model.query = "> uptime"
        let row = try? #require(model.results.first?.item)
        #expect(row?.title == "Run uptime")
        #expect(model.rootActions(for: row ?? .settings).map { $0?.title ?? "-" } == ["Run", "Show Manual for uptime", "Run and Show Output", "Run and Copy Output", "Run in Finder\u{2019}s Folder", "Run in Terminal", "Save as Script Command…", "-", "Copy Command"])
        model.shell.hasProgram = { $0 == "tldr" }
        #expect(model.rootActions(for: row ?? .settings).map { $0?.title ?? "-" }.prefix(3) == ["Run", "Show Manual for uptime", "Show Examples for uptime"], "offered on a Mac that has tldr")
        model.shell.hasProgram = { _ in false }
        model.activate(row ?? .settings)
        for _ in 0 ..< 100 where said.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(ran.all == ["uptime"])
        #expect(said == ["ok"])
        #expect(model.query.isEmpty)
        #expect(usage.queries == ["> uptime"], "Up brings the command back")
        #expect(usage.records.isEmpty, "a command has no place in the usage counts")

        model.runShellCommand("uptime", terminal: nil, showingOutput: true)
        for _ in 0 ..< 100 where shown.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(shown == ["uptime: ok\nand the rest"], "the whole output goes to the window, and the HUD stays quiet")
        #expect(said == ["ok"])

        model.runShellCommand("man rsync", terminal: nil)
        for _ in 0 ..< 100 where shown.count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(ran.all.last == "MANWIDTH=90 man -P cat rsync 2>&1 | col -bx", "a manual is asked for as plain text")
        #expect(shown.count == 2, "and is read in the window, whichever key ran it")

        model.shell.finderFolder = { URL(fileURLWithPath: "/tmp/project") }
        model.runInFinderFolder("git status", terminal: nil)
        for _ in 0 ..< 100 where shown.count < 3 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(ran.all.last == "git status in /tmp/project")

        model.shell.finderFolder = { throw SelectionError.finderEmpty }
        let before = ran.all.count
        model.runInFinderFolder("git status", terminal: nil)
        #expect(ran.all.count == before, "with no folder to run in, nothing runs")
        #expect(said.count == 2)

        model.settings.shell.runs = false
        model.query = "> uptime"
        #expect(model.results.first?.item.id != "shell-command")
    }
}
