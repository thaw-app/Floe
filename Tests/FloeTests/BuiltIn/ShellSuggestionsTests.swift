//
//  ShellSuggestionsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ShellSuggestionsTests {
    private func texts(_ typed: String, history: [String] = [], programs: [String] = [], entries: [String: [String]] = [:]) -> [String] {
        ShellSuggestions.suggestions(for: typed, history: history, programs: programs) { entries[$0] ?? [] }.map(\.text)
    }

    @Test func historyThatStartsAsTypedComesBeforeHistoryThatOnlyHoldsIt() {
        let history = ["brew upgrade", "git pull", "sudo brew doctor", "brew list", "git pull"]
        #expect(texts("brew", history: history) == ["brew upgrade", "brew list", "sudo brew doctor"])
        #expect(texts("git pull", history: history).isEmpty, "the command as typed is not offered back")
        #expect(texts("", history: history) == ["brew upgrade", "git pull", "sudo brew doctor", "brew list"], "nothing typed yet: the newest, each once")
        #expect(texts("zzz", history: history).isEmpty)
    }

    @Test func aProgramsNameIsFinishedOnlyWhileItIsTheOneWordTyped() {
        let programs = ["pkgbuild", "pkgutil", "pkill", "ps"]
        #expect(texts("pk", programs: programs) == ["pkgbuild ", "pkgutil ", "pkill "])
        #expect(texts("pkill", programs: programs).isEmpty, "a name typed in full has nothing to finish")
        #expect(texts("pkill ", programs: programs).isEmpty)
        #expect(texts("sudo pk", programs: programs).isEmpty)
    }

    @Test func aPathIsFinishedFromTheFolderItNames() {
        let entries = ["~/": ["Desktop/", "Documents/", "Downloads/", ".zshrc", "notes.txt"], "~/Documents/": ["My Notes.txt", "more/"], "/": ["usr/", "Users/"]]
        #expect(texts("open ~/D", entries: entries) == ["open ~/Desktop/", "open ~/Documents/", "open ~/Downloads/"])
        #expect(texts("cat ~/Documents/my", entries: entries) == ["cat ~/Documents/My\\ Notes.txt"], "letters match in either case, and a space is escaped")
        #expect(texts("cat ~/.z", entries: entries) == ["cat ~/.zshrc"])
        #expect(!texts("cat ~/", entries: entries).contains("cat ~/.zshrc"), "hidden files wait for the dot")
        #expect(texts("ls /u", entries: entries) == ["ls /Users/", "ls /usr/"])
        #expect(texts("ls u", entries: entries).isEmpty, "a word that is not a path is left alone")
        #expect(texts("open ~/D ", entries: entries).isEmpty, "a finished word has nothing to finish")
    }

    @Test func anApplicationIsFinishedAfterOpenAndAHostAfterSSH() {
        let apps = ["Safari", "Script Editor", "System Settings", "Notes"]
        let hosts = ["build-box", "bastion", "web1"]
        func names(_ typed: String) -> [String] {
            ShellSuggestions.names(for: typed, apps: apps, hosts: hosts)
        }
        #expect(names("open -a S") == ["open -a Safari", "open -a \"Script Editor\"", "open -a \"System Settings\""])
        #expect(names("open -a script e") == ["open -a \"Script Editor\""], "a name with a space in it is quoted")
        #expect(names("open -a Safari").isEmpty, "a name typed in full has nothing to finish")
        #expect(names("open -a ") == ["open -a Safari", "open -a \"Script Editor\"", "open -a \"System Settings\"", "open -a Notes"])
        #expect(names("open S").isEmpty)
        #expect(names("ssh b") == ["ssh build-box", "ssh bastion"])
        #expect(names("ssh ") == ["ssh build-box", "ssh bastion", "ssh web1"])
        #expect(names("scp file.txt w") == ["scp file.txt web1"])
        #expect(names("ssh").isEmpty)
        #expect(names("ssh -").isEmpty, "a flag is not a host")
        #expect(names("ls b").isEmpty)
        #expect(texts("ssh b", history: ["ssh build-box uptime"]) == ["ssh build-box uptime"], "with no hosts known, the history still answers")
    }

    @Test func noMoreThanTheLimitAndEachOnce() {
        let history = (0 ..< 20).map { "git log -\($0)" }
        #expect(texts("git", history: history + history).count == 5)
        #expect(texts("g", history: ["git "], programs: ["git"]) == ["git "], "the same line from two places is one row")
        #expect(ShellSuggestions.suggestions(for: "g", history: (0 ..< 9).map { "g\($0)" } + (0 ..< 9).map { "x g\($0)" }, programs: ["ga", "gb", "gc"]) { _ in [] }.count == ShellSuggestions.limit)
    }

    @Test func aSuggestionSaysWhetherItRunsOrOnlyFinishesTyping() {
        let found = ShellSuggestions.suggestions(for: "gi", history: ["git pull"], programs: ["git"]) { _ in [] }
        #expect(found == [ShellRow(text: "git pull", origin: .history), ShellRow(text: "git ", origin: .completion)])
    }

    @Test func aHistoryFileIsReadNewestFirstWithZshTimesTakenOff() {
        let text = """
        ls -la
        : 1700000000:0;git status
        : 1700000050:12;brew upgrade
        heap Droppy > /tmp/b.txt; \\
        diff /tmp/a.txt /tmp/b.txt
        ls -la

          spaced  \n
        """
        #expect(ShellHistory.commands(in: text) == ["spaced", "ls -la", "brew upgrade", "git status"])
        #expect(ShellHistory.commands(in: "").isEmpty)
        #expect(ShellHistory.commands(in: String(repeating: "x", count: 301)).isEmpty, "a line that long is no command to offer")
    }

    @Test func theHistoryIsTheFirstFileThereIsAndIsReadAgainWhenItChanges() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("floe-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let files = ShellHistory.files(environment: ["HISTFILE": home.appendingPathComponent("custom").path], home: home)
        #expect(files.map(\.lastPathComponent) == ["custom", ".zsh_history", ".bash_history"])
        #expect(ShellHistory.commands(from: files).isEmpty, "no file yet")

        let bash = home.appendingPathComponent(".bash_history")
        try Data("ls\npwd\n".utf8).write(to: bash)
        #expect(ShellHistory.commands(from: files) == ["pwd", "ls"])

        try Data("ls\npwd\nwhoami\n".utf8).write(to: bash)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: bash.path)
        #expect(ShellHistory.commands(from: files) == ["whoami", "pwd", "ls"])
    }

    @Test func onlyTheEndOfALongHistoryIsRead() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("floe-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".zsh_history")
        let lines = (0 ..< 40000).map { "echo line number \($0)" }.joined(separator: "\n") + "\n"
        try Data(lines.utf8).write(to: file)
        let commands = ShellHistory.commands(from: [file])
        #expect(commands.first == "echo line number 39999")
        #expect(commands.count < 40000)
        #expect(commands.allSatisfy { $0.hasPrefix("echo line number ") }, "the line the read began inside is left out")
    }

    @Test func foldersOnDiskEndInASlash() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-entries-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("inner"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("file.txt"))
        #expect(ShellSuggestions.entriesOnDisk(folder.path + "/").sorted() == ["file.txt", "inner/"])
        #expect(ShellSuggestions.entriesOnDisk("/floe-no-such-folder/").isEmpty)
        #expect(ShellSuggestions.programsOnPath().contains("ls"))
    }
}
