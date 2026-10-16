//
//  WindowSearchScopeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

@MainActor struct WindowSearchScopeTests {
    private let windows = [
        OpenWindow(id: "1:0", title: "Invoice March.pdf", appName: "Preview"),
        OpenWindow(id: "2:0", title: "Inbox", appName: "Mail"),
        OpenWindow(id: "2:1", title: "Re: invoice", appName: "Mail", isMinimized: true),
    ]

    private func scope(trusted: Bool = true) -> WindowSearchScope {
        WindowSearchScope(isTrusted: { trusted }, scan: { [windows] in windows })
    }

    private func titles(_ query: String) async -> [String] {
        let scope = scope()
        let context = SearchContext(query: query)
        guard let text = scope.text(in: context), let updates = scope.updates(for: text, context: context) else { return [] }
        var rows: [RootItem] = []
        for await batch in updates {
            rows = batch
        }
        return rows.map(\.title)
    }

    @Test func theWordAloneListsEveryWindowAndTextNarrowsThem() async {
        #expect(await titles("windows") == ["Invoice March.pdf", "Inbox", "Re: invoice"])
        #expect(await Set(titles("windows invoice")) == ["Invoice March.pdf", "Re: invoice"])
        #expect(await titles("Windows mail") == ["Inbox", "Re: invoice"], "an app's name finds its windows")
        #expect(await titles("windows zzz").isEmpty)
    }

    @Test func anotherWordIsNotTheScope() {
        #expect(scope().text(in: SearchContext(query: "window")) == nil)
        #expect(scope().text(in: SearchContext(query: "windowserver")) == nil)
        #expect(scope().text(in: SearchContext(query: "windows")) == "")
    }

    @Test func withoutAccessibilityOneRowSaysSo() {
        let scope = scope(trusted: false)
        let context = SearchContext(query: "windows")
        #expect(scope.results(for: "", context: context).map(\.id) == ["window-access"])
        #expect(scope.updates(for: "", context: context) == nil)
        #expect(self.scope().results(for: "", context: context).isEmpty, "with access the rows come from the scan")
    }

    @Test func aWindowRowIsLabelledByItsAppAndKeepsNoPlace() {
        let row = RootItem.window(.window(windows[2]))
        #expect(row.id == "window:2:1")
        #expect(row.rowLabel == "Mail, minimized")
        #expect(RootItem.window(.window(windows[0])).rowLabel == "Preview")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(OpenWindows.focus(windows[0]) == false, "a window with no element behind it cannot be raised")
    }
}

@MainActor struct WindowRowTests {
    private let model: LauncherModel

    init() throws {
        let defaults = MemoryDefaults()
        model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
    }

    @Test func aWindowOffersMinimizeOnlyWhileItIsNotMinimized() {
        let open = OpenWindow(id: "1:0", title: "Inbox", appName: "Mail")
        let minimized = OpenWindow(id: "1:1", title: "Draft", appName: "Mail", isMinimized: true)
        #expect(model.features.windows.windowActions(for: open).compactMap { $0?.title } == ["Minimize Window", "Close Window"])
        #expect(model.features.windows.windowActions(for: minimized).compactMap { $0?.title } == ["Close Window"])
        #expect(WindowRows.title(for: .window(open)) == "Switch to Window")
        #expect(WindowRows.title(for: .access) == "Open Privacy Settings")
    }

    @Test func aWindowThatWasNotReadFromAnAppIsLeftAlone() {
        let window = OpenWindow(id: "1:0", title: "Inbox", appName: "Mail")
        #expect(!OpenWindows.focus(window))
        #expect(!OpenWindows.minimize(window))
        #expect(!OpenWindows.close(window))
        for action in model.features.windows.windowActions(for: window) {
            action?.run()
        }
    }

    @Test func anActionOnAWindowReadsTheWindowsAgain() async throws {
        let defaults = MemoryDefaults()
        let scans = Mutex(0)
        let window = OpenWindow(id: "1:0", title: "Inbox", appName: "Mail")
        let scope = WindowSearchScope(isTrusted: { true }, scan: {
            scans.withLock { $0 += 1 }
            return [window]
        })
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [scope], sources: [])
        model.query = "windows"
        for _ in 0 ..< 1000 where model.results.isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(scans.withLock { $0 } == 1)
        model.features.windows.windowActions(for: window).last??.run()
        for _ in 0 ..< 1000 where scans.withLock({ $0 }) < 2 {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(scans.withLock { $0 } == 2, "the list is read again, so a closed window leaves it")
    }
}
