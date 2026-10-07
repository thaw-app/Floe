//
//  CustomIconTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing

struct CustomIconTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-icon-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func picture(in folder: URL, named name: String) throws -> URL {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let url = folder.appendingPathComponent(name)
        try #require(image.tiffRepresentation).write(to: url)
        return url
    }

    @Test func aChosenPictureIsKeptAsAPNGAndAnExtensionWithoutOneHasNone() throws {
        let data = try scratch()
        defer { try? FileManager.default.removeItem(at: data) }
        #expect(CustomIcon.path(for: "notes", in: data) == nil)

        try CustomIcon.set(picture(in: data, named: "red.tiff"), for: "notes", in: data, stamp: 1)
        let path = try #require(CustomIcon.path(for: "notes", in: data))
        #expect(path.hasSuffix("/notes/custom-icon-1.png"))
        #expect(NSImage(contentsOfFile: path) != nil)
        #expect(CustomIcon.path(for: "other", in: data) == nil)
    }

    @Test func aSecondPictureTakesTheFirstOnesPlaceUnderANewName() throws {
        let data = try scratch()
        defer { try? FileManager.default.removeItem(at: data) }
        let source = try picture(in: data, named: "red.tiff")
        try CustomIcon.set(source, for: "notes", in: data, stamp: 1)
        try CustomIcon.set(source, for: "notes", in: data, stamp: 2)
        #expect(CustomIcon.path(for: "notes", in: data)?.hasSuffix("custom-icon-2.png") == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: data.appendingPathComponent("notes").path) == ["custom-icon-2.png"])

        CustomIcon.remove(for: "notes", in: data)
        #expect(CustomIcon.path(for: "notes", in: data) == nil)
    }

    @Test func aFileThatIsNoPictureIsRefusedAndTheOldOneStays() throws {
        let data = try scratch()
        defer { try? FileManager.default.removeItem(at: data) }
        try CustomIcon.set(picture(in: data, named: "red.tiff"), for: "notes", in: data, stamp: 1)
        let text = data.appendingPathComponent("notes.txt")
        try Data("not a picture".utf8).write(to: text)
        #expect(throws: CocoaError.self) { try CustomIcon.set(text, for: "notes", in: data, stamp: 2) }
        #expect(CustomIcon.path(for: "notes", in: data)?.hasSuffix("custom-icon-1.png") == true)
    }
}
