//
//  ScriptRunnerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ScriptRunnerTests {
    @Test(arguments: [
        ("one", ["one"]),
        ("open file", ["open", "file"]),
        ("  a \t b\n c  ", ["a", "b", "c"]),
        ("", []),
        (" \t\n ", []),
    ])
    func wordsAreSplitOnAnyRunOfWhitespace(text: String, expected: [String]) {
        #expect(ScriptRunner.splitArguments(text) == expected)
    }

    @Test(arguments: [
        (#""two words" three"#, ["two words", "three"]),
        ("'two words' three", ["two words", "three"]),
        (#""  padded  ""#, ["  padded  "]),
        ("\"a\tb\nc\"", ["a\tb\nc"]),
        (#""it's" 'say "hi"'"#, ["it's", #"say "hi""#]),
    ])
    func aQuotedSpanIsOneWordWithItsWhitespaceAndTheOtherKindOfQuoteKept(text: String, expected: [String]) {
        #expect(ScriptRunner.splitArguments(text) == expected)
    }

    @Test(arguments: [
        ("\"\"", [""]),
        ("''", [""]),
        (#"a "" b"#, ["a", "", "b"]),
        ("\"\" ''", ["", ""]),
    ])
    func anEmptyQuotedSpanIsAnEmptyArgument(text: String, expected: [String]) {
        #expect(ScriptRunner.splitArguments(text) == expected)
    }

    @Test(arguments: [
        (#"a"b c"d"#, ["ab cd"]),
        (#"--name="Ada L" next"#, ["--name=Ada L", "next"]),
        (#""a"'b'c"#, ["abc"]),
        (#"a""b"#, ["ab"]),
    ])
    func quotedAndUnquotedPartsThatTouchAreOneWord(text: String, expected: [String]) {
        #expect(ScriptRunner.splitArguments(text) == expected)
    }

    @Test(arguments: [
        (#""say \"hi\"" now"#, [#"say "hi""#, "now"]),
        (#"'it\'s' here"#, ["it's", "here"]),
        (#""a\\b""#, [#"a\b"#]),
        (#""a\nb""#, ["anb"]),
        (#""a\ b""#, ["a b"]),
    ])
    func insideEitherKindOfQuoteABackslashKeepsTheNextCharacterAndIsDropped(text: String, expected: [String]) {
        #expect(ScriptRunner.splitArguments(text) == expected)
    }

    @Test(arguments: [
        (#"\"#, [#"\"#]),
        (#"a\ b"#, [#"a\"#, "b"]),
        (#"C:\Users\ada"#, [#"C:\Users\ada"#]),
        (#"\"a b\""#, [#"\a b""#]),
    ])
    func outsideQuotesABackslashIsAnOrdinaryCharacter(text: String, expected: [String]) {
        #expect(ScriptRunner.splitArguments(text) == expected)
    }

    @Test(arguments: [
        (#""a b"#, ["a b"]),
        (#"a "b c"#, ["a", "b c"]),
        ("\"", [""]),
        ("a '", ["a", ""]),
        (#"'a\' b"#, ["a' b"]),
        (#""abc\"#, ["abc"]),
    ])
    func anUnterminatedQuoteRunsToTheEndOfTheText(text: String, expected: [String]) {
        #expect(ScriptRunner.splitArguments(text) == expected)
    }

    @Test(arguments: [
        ("one\ntwo\nthree", "three"),
        ("one\n  two  \n\n   \n", "two"),
        ("first\r\nlast\r\n", "last"),
        ("only", "only"),
        ("", nil),
        (" \n\t\n", nil),
    ] as [(String, String?)])
    func theLastLineIsTheLastOneWithTextTrimmed(text: String, expected: String?) {
        #expect(ScriptRunner.lastLine(text) == expected)
    }

    @Test func theTemplateIsABashScriptThatGreetsWithItsTitle() {
        let lines = ScriptRunner.template(title: "Tidy Desktop").components(separatedBy: "\n")
        #expect(lines.first == "#!/bin/bash")
        #expect(lines.contains("# @raycast.title Tidy Desktop"))
        #expect(lines.last == #"echo "Hello from Tidy Desktop!""#)
        #expect(ScriptRunner.template().contains("# @raycast.title My Script\n"))
    }

    @Test func theTemplateParsesBackAsACommand() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-script-template-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("tidy.sh")
        try ScriptRunner.template(title: "Tidy Desktop").write(to: file, atomically: true, encoding: .utf8)

        let command = try ScriptCommand.parse(file: file).get()
        #expect(command == ScriptCommand(
            file: file,
            title: "Tidy Desktop",
            packageName: "Scripts",
            mode: .fullOutput,
            needsConfirmation: false,
            icon: "🤖",
            arguments: []
        ))
    }

    @Test func aScriptRunsInItsOwnFolderWithTheArgumentsAsGiven() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-script-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "beside the script".write(to: folder.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        let file = folder.appendingPathComponent("echo.sh")
        try """
        #!/bin/sh
        # @raycast.schemaVersion 1
        # @raycast.title Echo
        printf '<%s>' "$@"
        cat marker.txt
        echo oops >&2
        exit 3
        """.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        let command = try ScriptCommand.parse(file: file).get()
        let result = try await ScriptRunner.run(command, arguments: ["one", "two words", ""])
        #expect(result.output == "<one><two words><>beside the script")
        #expect(String(data: result.stderr, encoding: .utf8) == "oops\n")
        #expect(result.status == 3)
        #expect(!result.succeeded)
        #expect(ScriptRunner.timeout == 60)
    }

    @Test func anActionScriptIsToldTheResultInItsEnvironment() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-script-env-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("show.sh")
        try """
        #!/bin/sh
        # @raycast.schemaVersion 1
        # @raycast.title Show
        # @floe.subjects file
        printf '%s|%s|%s' "$FLOE_NAME" "$FLOE_PARENT" "${HOME:+home}"
        """.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        let command = try ScriptCommand.parse(file: file).get()
        let name = "it's \"$(echo no)\".txt"
        let subject = ActionSubject(kind: .file, name: name, url: folder.appendingPathComponent(name))
        let result = try await ScriptRunner.run(command, arguments: [], environment: subject.environment(facts: SubjectFacts(), query: ""))
        #expect(result.output == "\(name)|\(folder.standardizedFileURL.path(percentEncoded: false).replacing(/\/$/, with: ""))|home", "the name arrives as it is, beside the login shell's own variables")
    }
}
