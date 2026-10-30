//
//  FinderSelectionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct FinderSelectionTests {
    @Test func aLineBreakInAFilesNameStaysInThatOnePath() {
        let answer = "47,116,109,112,47,97,10,47,101,116,99\n47\n"
        #expect(FinderSelection.paths(inAnswer: answer) == ["/tmp/a\n/etc", "/"])
    }

    @Test func anAnswerThatIsNotNumbersNamesNoPath() {
        #expect(FinderSelection.paths(inAnswer: "/Users/someone/a.txt\n47,120") == ["/x"])
        #expect(FinderSelection.paths(inAnswer: "55296\n1114112\n\n").isEmpty, "a lone surrogate or a number past Unicode is no character")
    }

    @Test func theScriptsNumbersReadBackAsThePathsItWasGiven() async {
        let script = FinderSelection.codesHandler + #"""

        return my codes("/tmp/a" & linefeed & "/etc/passwd") & linefeed & my codes("/") & linefeed & my codes("/tmp/é" & (character id 769) & "😀")
        """#
        let answer = await AppleScript.execute(script)
        #expect(FinderSelection.paths(inAnswer: answer.text ?? "") == ["/tmp/a\n/etc/passwd", "/", "/tmp/é\u{301}😀"])
    }
}
