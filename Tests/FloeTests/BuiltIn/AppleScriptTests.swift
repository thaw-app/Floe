//
//  AppleScriptTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct AppleScriptTests {
    @Test func anAnswerLosesOnlyTheLineBreakOsascriptAdds() {
        let execution = AppleScript.Execution(status: 0, output: "one\ntwo\n\n", errors: "")
        #expect(execution == AppleScript.Execution(text: "one\ntwo\n"))
    }

    @Test func aScriptThatAnswersNothingRanAndHasNoError() {
        let execution = AppleScript.Execution(status: 0, output: "", errors: "")
        #expect(execution.didRun)
        #expect(!execution.hasError)
        #expect(execution.text?.isEmpty == true)
    }

    @Test func aRefusalIsReadFromTheErrorLine() {
        let line = "36:44: execution error: Not authorized to send Apple events to Safari. (-1743)\n"
        let execution = AppleScript.Execution(status: 1, output: "", errors: line)
        #expect(execution.isRefused)
        #expect(execution.errorMessage == "Not authorized to send Apple events to Safari.")
        #expect(!execution.didRun)
    }

    @Test func aSyntaxErrorKeepsItsNumberAndAMessageOverTwoLines() {
        let execution = AppleScript.Execution(status: 1, output: "", errors: "0:3: syntax error: Expected end\nof line. (-2741)\n")
        #expect(execution.errorNumber == -2741)
        #expect(execution.errorMessage == "Expected end\nof line.")
    }

    @Test func anErrorWithoutANumberIsStillAnError() {
        let execution = AppleScript.Execution(status: 1, output: "", errors: "osascript: no such file\n")
        #expect(execution.hasError)
        #expect(execution.errorNumber == nil)
        #expect(execution.errorMessage == "osascript: no such file")
    }

    @Test func aScriptRunsInOsascriptAndItsErrorComesBack() async {
        #expect(await AppleScript.run("return \"día\" & linefeed & 2") == .text("día\n2"))
        #expect(await AppleScript.execute("error \"No.\" number -1743").isRefused)
    }

    @Test func aLiteralKeepsAQuoteOrBackslashWithACombiningMarkInsideTheString() async {
        let text = "a\"\u{0301} & (do shell script \"id\") & \\\u{0301}\""
        #expect(AppleScript.literal(text) == "\"a\\\"\u{0301} & (do shell script \\\"id\\\") & \\\\\u{0301}\\\"\"")
        #expect(await AppleScript.run("return " + AppleScript.literal(text)) == .text(text), "the script reads back the text, not a command")
    }
}
