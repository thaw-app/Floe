//
//  SelectedTextTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// The Command-C fallback, on a pasteboard of the test's own and with the keystroke replaced.
struct SelectedTextTests {
    @Test func aCopyThatCopiesNothingIsNoSelectionAndNotWhatWasCopiedBefore() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        await #expect(throws: SelectionError.self) {
            try await SelectedText.copiedSelectedText(from: pasteboard, copy: {})
        }
        #expect(pasteboard.string(forType: .string) == "hunter2")
    }

    @Test func aFreshCopyIsTheSelectionAndTheClipboardComesBack() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)
        let text = try await SelectedText.copiedSelectedText(from: pasteboard) {
            pasteboard.clearContents()
            pasteboard.setString("the selection", forType: .string)
        }
        #expect(text == "the selection")
        #expect(pasteboard.string(forType: .string) == "before")
    }
}
