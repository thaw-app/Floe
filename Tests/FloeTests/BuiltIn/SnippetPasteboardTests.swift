//
//  SnippetPasteboardTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor struct SnippetPasteboardTests {
    private let signature = "Best,\nOwen"

    /// A pasteboard of the test's own, so the user's clipboard is never read or written.
    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    private func isSkipped(_ pasteboard: NSPasteboard) -> Bool {
        if case .skipped = ClipboardCapture.reading(pasteboard) {
            return true
        }
        return false
    }

    @Test func aLentSnippetIsLeftOutOfTheHistory() {
        withPasteboard { pasteboard in
            PasteboardContent.write(text: "mine", html: nil, file: nil, to: pasteboard)
            _ = SnippetPasteboard.lend(signature, to: pasteboard, after: nil)
            #expect(pasteboard.string(forType: .string) == signature)
            #expect(isSkipped(pasteboard))
        }
    }

    @Test func givingBackRestoresWhatWasCopiedWithoutRecordingItAgain() {
        withPasteboard { pasteboard in
            PasteboardContent.write(text: "mine", html: nil, file: nil, to: pasteboard)
            let loan = SnippetPasteboard.lend(signature, to: pasteboard, after: nil)
            #expect(SnippetPasteboard.giveBack(loan, to: pasteboard))
            #expect(pasteboard.string(forType: .string) == "mine")
            #expect(isSkipped(pasteboard))
        }
    }

    @Test func aNewerCopyIsNotOverwritten() {
        withPasteboard { pasteboard in
            PasteboardContent.write(text: "mine", html: nil, file: nil, to: pasteboard)
            let loan = SnippetPasteboard.lend(signature, to: pasteboard, after: nil)
            PasteboardContent.write(text: "newer", html: nil, file: nil, to: pasteboard)
            #expect(!SnippetPasteboard.giveBack(loan, to: pasteboard))
            #expect(pasteboard.string(forType: .string) == "newer")
        }
    }

    @Test func everyTypeOfEveryItemComesBack() throws {
        try withPasteboard { pasteboard in
            let custom = NSPasteboard.PasteboardType("app.floe.tests.custom")
            let first = NSPasteboardItem()
            first.setString("one", forType: .string)
            first.setData(Data([1, 2, 3]), forType: custom)
            let second = NSPasteboardItem()
            second.setString("two", forType: .string)
            pasteboard.clearContents()
            pasteboard.writeObjects([first, second])

            let loan = SnippetPasteboard.lend(signature, to: pasteboard, after: nil)
            #expect(SnippetPasteboard.giveBack(loan, to: pasteboard))

            let items = try #require(pasteboard.pasteboardItems)
            #expect(items.map { $0.string(forType: .string) } == ["one", "two"])
            #expect(items[0].data(forType: custom) == Data([1, 2, 3]))
            #expect(items[1].data(forType: custom) == nil)
        }
    }

    @Test func anEmptyPasteboardIsLeftEmpty() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            let loan = SnippetPasteboard.lend(signature, to: pasteboard, after: nil)
            #expect(SnippetPasteboard.giveBack(loan, to: pasteboard))
            #expect(pasteboard.types?.isEmpty != false)
        }
    }

    @Test func aSecondExpansionKeepsWhatWasCopiedBeforeTheFirst() {
        withPasteboard { pasteboard in
            PasteboardContent.write(text: "mine", html: nil, file: nil, to: pasteboard)
            let first = SnippetPasteboard.lend(signature, to: pasteboard, after: nil)
            let second = SnippetPasteboard.lend("Cheers", to: pasteboard, after: first)
            #expect(pasteboard.string(forType: .string) == "Cheers")
            #expect(SnippetPasteboard.giveBack(second, to: pasteboard))
            #expect(pasteboard.string(forType: .string) == "mine")
        }
    }

    @Test func aCopyBetweenTwoExpansionsIsWhatComesBack() {
        withPasteboard { pasteboard in
            PasteboardContent.write(text: "mine", html: nil, file: nil, to: pasteboard)
            let first = SnippetPasteboard.lend(signature, to: pasteboard, after: nil)
            PasteboardContent.write(text: "between", html: nil, file: nil, to: pasteboard)
            let second = SnippetPasteboard.lend("Cheers", to: pasteboard, after: first)
            #expect(SnippetPasteboard.giveBack(second, to: pasteboard))
            #expect(pasteboard.string(forType: .string) == "between")
        }
    }
}
