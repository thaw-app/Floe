//
//  QuicklinkImportTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct QuicklinkImportTests {
    private let apps = QuicklinkImport.Apps(home: URL(fileURLWithPath: "/Users/me"), app: { _ in nil })

    private func plan(_ links: [RaycastQuicklink], existing: [Quicklink] = []) -> QuicklinkImport.Plan {
        QuicklinkImport.plan(links, existing: existing, apps: apps)
    }

    @Test func aSearchBecomesAFloeSearchWithAKeywordFromItsName() {
        let result = plan([RaycastQuicklink(name: "Search DuckDuckGo", link: "https://duckduckgo.com/?q={argument}")])
        #expect(result.added.map(\.name) == ["Search DuckDuckGo"])
        #expect(result.added.map(\.keyword) == ["sd"])
        #expect(result.added.map(\.url) == ["https://duckduckgo.com/?q={query}"])
        #expect(result.skipped.isEmpty)
    }

    @Test func aKeywordInUseGetsANumber() {
        let google = Quicklink(name: "Google", keyword: "g", url: "https://www.google.com/search?q={query}")
        let result = plan([
            RaycastQuicklink(name: "GitHub", link: "https://github.com"),
            RaycastQuicklink(name: "GitLab", link: "https://gitlab.com"),
            RaycastQuicklink(name: "Go Docs", link: "https://go.dev/doc"),
            RaycastQuicklink(name: "Gmail", link: "https://mail.google.com"),
            RaycastQuicklink(name: "G", link: "https://g.example"),
        ], existing: [Quicklink(name: "Mine", keyword: "GitHub", url: "https://mine.example"), google])
        #expect(result.added.map(\.keyword) == ["github2", "gitlab", "gd", "gmail", "g2"])
    }

    @Test func aLinkWithMoreThanFloeCanFillIsSkippedAndSaysWhy() {
        let result = plan([
            RaycastQuicklink(name: "Translate", link: "https://t.example/?from={argument name=\"from\"}&to={argument name=\"to\"}"),
            RaycastQuicklink(name: "Two", link: "https://two.example/{argument}/{argument}"),
            RaycastQuicklink(name: "Earlier", link: "https://p.example/?q={clipboard offset=1}"),
            RaycastQuicklink(name: "Today", link: "https://d.example/{date format=\"yyyy-MM-dd\"}"),
            RaycastQuicklink(name: "Same", link: "https://s.example/{argument name=\"q\"}?again={argument name=\"q\" default=\"x\"}"),
        ])
        #expect(result.skipped == [
            .init(name: "Translate", reason: .severalArguments),
            .init(name: "Two", reason: .severalArguments),
            .init(name: "Earlier", reason: .placeholder("clipboard offset=1")),
            .init(name: "Today", reason: .placeholder("date")),
        ])
        #expect(result.added.map(\.url) == ["https://s.example/{query}?again={query}"])
    }

    @Test func theSelectionAndTheClipboardAreKeptForFloeToFill() {
        let result = plan([
            RaycastQuicklink(name: "Look Up", link: "https://s.example/?q={Selection | percent-encode}"),
            RaycastQuicklink(name: "Paste", link: "https://p.example/{argument}?from={clipboard}"),
            RaycastQuicklink(name: "Notes", link: "~/Notes/{selection}.md"),
        ])
        #expect(result.added.map(\.url) == [
            "https://s.example/?q={selection}",
            "https://p.example/{query}?from={clipboard}",
            "file:///Users/me/Notes/{selection}.md",
        ])
        #expect(result.skipped.isEmpty)
    }

    @Test func anArgumentThatRaycastChangesIsSkippedAndOneItEncodesIsKept() {
        let result = plan([
            RaycastQuicklink(name: "Ticket", link: "https://t.example/{argument name=\"id\" | uppercase}"),
            RaycastQuicklink(name: "Search", link: "https://s.example/?q={argument | percent-encode}"),
        ])
        #expect(result.skipped == [.init(name: "Ticket", reason: .placeholder("argument | uppercase"))])
        #expect(result.added.map(\.url) == ["https://s.example/?q={query}"])
    }

    @Test func aFolderBecomesAFileLinkAndAnythingWithoutASchemeIsSkipped() {
        let result = plan([
            RaycastQuicklink(name: "Downloads", link: "~/Downloads"),
            RaycastQuicklink(name: "Apps", link: "/Applications"),
            RaycastQuicklink(name: "Nowhere", link: "just some words"),
        ])
        #expect(result.added.map(\.url) == ["file:///Users/me/Downloads", "file:///Applications"])
        #expect(result.skipped == [.init(name: "Nowhere", reason: .notALink)])
    }

    @Test func aPathKeepsItsSearchTerm() {
        let result = plan([
            RaycastQuicklink(name: "Notes", link: "~/Notes/{argument}.md"),
            RaycastQuicklink(name: "Tmp", link: "/tmp/{query}"),
        ])
        #expect(result.added.map(\.url) == ["file:///Users/me/Notes/{query}.md", "file:///tmp/{query}"])
        #expect(result.added.map(\.symbol) == ["magnifyingglass", "magnifyingglass"])
    }

    @Test func aNameWithoutLettersStillGetsAKeyword() {
        let result = plan([
            RaycastQuicklink(name: "🔍", link: "https://a.example"),
            RaycastQuicklink(name: "!!!", link: "https://b.example"),
        ])
        #expect(result.added.map(\.keyword) == ["link", "link2"])
    }

    @Test func aLinksAppIsKeptWhenThisMacHasIt() {
        let finder = AppChoice(bundleIdentifier: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app")
        let apps = QuicklinkImport.Apps(home: URL(fileURLWithPath: "/Users/me")) { $0 == "Finder" ? finder : nil }
        let result = QuicklinkImport.plan([
            RaycastQuicklink(name: "Downloads", link: "~/Downloads", openWith: "Finder"),
            RaycastQuicklink(name: "Repo", link: "https://github.com", openWith: "/Applications/Gone.app"),
            RaycastQuicklink(name: "Plain", link: "https://plain.example"),
        ], existing: [], apps: apps)
        #expect(result.added.map(\.openWith) == [finder, nil, nil])
        #expect(result.withoutApp == ["Repo"])
    }

    @Test func raycastIconsBecomeSymbolsAndTheRestGetOneForTheirKind() {
        let result = plan([
            RaycastQuicklink(name: "Downloads", link: "~/Downloads", iconName: "folder-16"),
            RaycastQuicklink(name: "Docs", link: "https://docs.example", iconName: "book-16"),
            RaycastQuicklink(name: "Search", link: "https://s.example/?q={argument}", iconName: "something-new-16"),
            RaycastQuicklink(name: "Home", link: "https://home.example"),
        ])
        #expect(result.added.map(\.symbol) == ["folder", "book", "magnifyingglass", "link"])
    }

    @Test func aLinkFloeHasAlreadyIsSkipped() {
        let docs = Quicklink(name: "Docs", keyword: "d", url: "https://docs.example/?q={query}")
        let result = plan([
            RaycastQuicklink(name: "Docs", link: "https://docs.example/?q={argument name=\"term\"}"),
            RaycastQuicklink(name: "Docs", link: "https://other.example"),
            RaycastQuicklink(name: "Docs", link: "https://other.example"),
        ], existing: [docs])
        #expect(result.added.map(\.url) == ["https://other.example"])
        #expect(result.skipped == [
            .init(name: "Docs", reason: .alreadyThere),
            .init(name: "Docs", reason: .alreadyThere),
        ])
    }
}
