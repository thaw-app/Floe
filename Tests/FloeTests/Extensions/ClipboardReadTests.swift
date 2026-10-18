//
//  ClipboardReadTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ClipboardReadTests {
    @Test func aClipboardReadKeepsItsOffsetAndTreatsANegativeOneAsTheCurrentCopy() {
        #expect(HostRequest(method: "clipboard.read", params: ["offset": 2]) == .clipboardRead(offset: 2))
        #expect(HostRequest(method: "clipboard.read", params: ["offset": -1]) == .clipboardRead(offset: 0))
    }

    @Test func anOlderCopyComesFromTheHistoryNewestFirst() {
        let directory = URL(fileURLWithPath: "/tmp/clips")
        func entry(_ kind: ClipboardEntry.Kind, text: String? = nil, files: [String]? = nil, image: String? = nil) -> ClipboardEntry {
            ClipboardEntry(id: UUID(), kind: kind, text: text, filePaths: files, imageFile: image, date: Date(), pinned: false)
        }
        let entries = [
            entry(.text, text: "now"), entry(.link, text: "https://example.com"), entry(.file, files: ["/a.txt", "/b.txt"]),
            entry(.image, text: "png", image: "shot.png"), entry(.text, text: "4"), entry(.text, text: "5"), entry(.text, text: "6"),
        ]
        #expect(PasteboardContent.copy(offset: 1, in: entries, directory: directory) == ["text": "https://example.com"])
        #expect(PasteboardContent.copy(offset: 2, in: entries, directory: directory) == ["text": "/a.txt", "file": "/a.txt"])
        #expect(PasteboardContent.copy(offset: 3, in: entries, directory: directory) == ["text": "", "file": "/tmp/clips/shot.png"])
        #expect(PasteboardContent.copy(offset: 5, in: entries, directory: directory) == ["text": "5"])
        #expect(PasteboardContent.copy(offset: 6, in: entries, directory: directory) == ["text": ""], "Raycast goes back five at most")
        #expect(PasteboardContent.copy(offset: 1, in: [], directory: directory) == ["text": ""], "no history, an empty slot")
    }

    @Test func theRunnerAnswersAnOlderCopyFromTheHistoryItWasHanded() async throws {
        let answer = ExtensionRunner.answer {
            ["now", "before"].map { ClipboardEntry(id: UUID(), kind: .text, text: $0, filePaths: nil, imageFile: nil, date: Date(), pinned: false) }
        }
        let result = try await answer(.clipboardRead(offset: 1)) { _ in }
        #expect(result as? [String: String] == ["text": "before"])
    }
}
