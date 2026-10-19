//
//  TypedPathTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct TypedPathTests {
    private static let home = "/Users/someone"

    @Test(arguments: [
        ("/Applications", "/Applications"),
        ("/Applications/", "/Applications"),
        ("/", "/"),
        ("~", "/Users/someone"),
        ("~/", "/Users/someone"),
        ("~/Downloads", "/Users/someone/Downloads"),
        ("~/Downloads/", "/Users/someone/Downloads"),
        ("~/Projects/launcher-proto/README.md", "/Users/someone/Projects/launcher-proto/README.md"),
        ("~/Documents/../Downloads", "/Users/someone/Downloads"),
        ("/usr/local/../bin/./swift", "/usr/bin/swift"),
        ("/../..", "/"),
        ("//usr///bin//", "/usr/bin"),
        ("/Applications/Visual Studio Code.app", "/Applications/Visual Studio Code.app"),
        ("  ~/My Files/a b.txt  ", "/Users/someone/My Files/a b.txt"),
        ("file:///Applications", "/Applications"),
    ])
    func aPathIsMadeAbsoluteFromItsTextAlone(typed: String, path: String) {
        #expect(TypedPath.standardized(typed, home: Self.home) == path)
    }

    @Test(arguments: ["", " ", "Downloads", "Downloads/x.txt", "./x", "../x", "notes.txt", "~someone", "~someone/x", "a/~", "safari", "file://server/Applications"])
    func aRelativePathOrAFileNameIsNotAPath(typed: String) {
        #expect(TypedPath.standardized(typed, home: Self.home) == nil)
        #expect(TypedPath.file(for: typed, home: Self.home) { _ in .file } == nil)
    }

    @Test func aFolderAndAFileBecomeTheRowTheFileSearchWouldMake() throws {
        let folder = try #require(TypedPath.file(for: "~/Downloads/", home: Self.home) { _ in .folder })
        #expect(folder.url.path == "/Users/someone/Downloads")
        #expect(folder.url.hasDirectoryPath)
        #expect(folder.name == "Downloads")
        #expect(folder.displayPath == "~")
        #expect(folder.id == "/Users/someone/Downloads")

        let file = try #require(TypedPath.file(for: "/usr/local/../share/a b.txt", home: Self.home) { _ in .file })
        #expect(file.url.path == "/usr/share/a b.txt")
        #expect(!file.url.hasDirectoryPath)
        #expect(file.name == "a b.txt")
        #expect(file.displayPath == "/usr/share")
        #expect(file.contentType == nil && file.lastUsed == nil)

        let inside = try #require(TypedPath.file(for: "~/Projects/floe/README.md", home: Self.home) { _ in .file })
        #expect(inside.displayPath == "~/Projects/floe")
        #expect(TypedPath.file(for: "~", home: Self.home) { _ in .folder }?.name == "someone")
    }

    @Test func thePathIsLookedUpOnceInItsStandardFormAndAMissingOneGivesNothing() {
        var asked: [String] = []
        let missing = TypedPath.file(for: "~/Documents/../nowhere/", home: Self.home) {
            asked.append($0)
            return nil
        }
        #expect(missing == nil)
        #expect(asked == ["/Users/someone/nowhere"])
    }

    @Test func theDiskSaysWhetherAPathIsAFileAFolderOrMissing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-typed-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a b.txt")
        try Data("x".utf8).write(to: file)
        #expect(TypedPath.kindOnDisk(folder.path) == .folder)
        #expect(TypedPath.kindOnDisk(file.path) == .file)
        #expect(TypedPath.kindOnDisk(folder.appendingPathComponent("missing").path) == nil)
    }
}
