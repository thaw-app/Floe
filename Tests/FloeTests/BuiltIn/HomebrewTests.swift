//
//  HomebrewTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

@MainActor final class HomebrewTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-brew-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// A Homebrew in a folder of the test's own: two formulae and a cask known, one formula and one cask installed.
    private func places(withBrew: Bool = true) throws -> Homebrew.Places {
        let manager = FileManager.default
        let prefix = root.appendingPathComponent("prefix")
        let cache = root.appendingPathComponent("cache")
        for folder in ["bin", "Cellar/ripgrep", "Cellar/.keepme", "Caskroom/ghostty"] {
            try manager.createDirectory(at: prefix.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        if withBrew {
            let brew = prefix.appendingPathComponent("bin/brew")
            try Data("#!/bin/sh\n".utf8).write(to: brew)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        }
        try Data("ffmpeg\nripgrep\nbad name; rm -rf ~\n--force\n".utf8).write(to: cache.appendingPathComponent("formula_names.txt"))
        try Data("ghostty\nvisual-studio-code\n".utf8).write(to: cache.appendingPathComponent("cask_names.txt"))
        return Homebrew.Places(prefixes: [root.appendingPathComponent("nowhere"), prefix], cache: cache)
    }

    @Test func thePackagesAreReadFromTheListsWithTheInstalledOnesFirst() throws {
        let packages = try Homebrew.read(places())
        #expect(packages.map(\.name) == ["ghostty", "ripgrep", "ffmpeg", "visual-studio-code"])
        #expect(packages.map(\.isInstalled) == [true, true, false, false])
        #expect(packages.map(\.isCask) == [true, false, false, true])
        #expect(packages.map(\.label) == ["Cask, installed", "Formula, installed", "Formula", "Cask"])
    }

    @Test func withoutHomebrewThereIsNothing() throws {
        #expect(try Homebrew.read(places(withBrew: false)).isEmpty)
    }

    @Test(arguments: ["bad name; rm -rf ~", "--force", "", "a$(b)", "a\nb", "-x"])
    func aNameThatWouldChangeTheCommandIsNeverOne(name: String) {
        #expect(!Homebrew.isSafe(name))
    }

    @Test func theCommandNamesTheVerbAndSaysWhenItIsACask() {
        let formula = BrewPackage(name: "python@3.13", isCask: false, isInstalled: false)
        let cask = BrewPackage(name: "ghostty", isCask: true, isInstalled: true)
        #expect(Homebrew.isSafe(formula.name))
        #expect(Homebrew.command(.install, formula) == "brew install python@3.13")
        #expect(Homebrew.command(.uninstall, cask) == "brew uninstall --cask ghostty")
        #expect(Homebrew.primaryVerb(for: formula) == .install)
        #expect(Homebrew.primaryVerb(for: cask) == .upgrade)
        #expect(BrewRows.title(for: .install) == "Install in Terminal")
        #expect(BrewRows.title(for: .upgrade) == "Upgrade in Terminal")
    }

    @Test func aQueryRanksByNameAndTheWordAloneListsWhatIsInstalled() throws {
        let packages = try Homebrew.read(places())
        #expect(Homebrew.ranked(packages, query: "").map(\.name) == ["ghostty", "ripgrep"])
        #expect(Homebrew.ranked(packages, query: "rip").map(\.name) == ["ripgrep"])
        #expect(Homebrew.ranked(packages, query: "zzz").isEmpty)
    }

    @Test func theScopeAnswersToItsWordAndGivesRowsOfItsOwn() async throws {
        let found = try Homebrew.read(places())
        let scope = BrewSearchScope(read: { found })
        #expect(scope.text(in: SearchContext(query: "brew rip")) == "rip")
        #expect(scope.text(in: SearchContext(query: "Brew")) == "")
        #expect(scope.text(in: SearchContext(query: "brewery")) == nil)
        let stream = try #require(scope.updates(for: "rip", context: SearchContext(query: "brew rip")))
        var rows: [RootItem] = []
        for await batch in stream {
            rows = batch
        }
        let row = try #require(rows.first)
        #expect(row.title == "ripgrep")
        #expect(row.id == "brew:formula:ripgrep")
        #expect(row.kind == "Homebrew")
        #expect(row.rowLabel == "Formula, installed")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(BrewRows().returnTitle(for: row) == "Upgrade in Terminal")
    }
}
