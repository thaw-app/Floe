//
//  PreferredAppsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Apps that are on no Mac, so no test reads the one it runs on.
private enum Fake {
    static let terminal = URL(fileURLWithPath: "/Fake/System/Terminal.app")
    static let ghostty = URL(fileURLWithPath: "/Fake/Applications/Ghostty.app")
    static let textEdit = URL(fileURLWithPath: "/Fake/System/TextEdit.app")
    static let zed = URL(fileURLWithPath: "/Fake/Applications/Zed.app")
    static let nova = URL(fileURLWithPath: "/Fake/Applications/Nova.app")
    static let apps = ["com.apple.Terminal": terminal, "com.mitchellh.ghostty": ghostty, "com.apple.TextEdit": textEdit, "dev.zed.Zed": zed]
}

@MainActor
struct PreferredAppsTests {
    /// A Mac with exactly these apps, whatever the one running the tests has.
    private func mac(
        _ apps: [String: URL] = Fake.apps,
        plainText: URL? = Fake.textEdit,
        onDisk: Set<URL> = []
    ) -> AppLookup {
        AppLookup(
            url: { apps[$0] },
            plainTextApp: { plainText },
            exists: { onDisk.contains($0) || apps.values.contains($0) },
            bundleIdentifier: { url in apps.first { $0.value == url }?.key }
        )
    }

    private func isFolder(_ url: URL) -> Bool {
        url.hasDirectoryPath
    }

    // MARK: Which app

    @Test func withNothingChosenTheTerminalIsTerminalAndTheEditorIsWhateverOpensPlainText() {
        #expect(PreferredApps.app(for: .terminal, choice: nil, installed: mac())?.name == "Terminal")
        #expect(PreferredApps.app(for: .editor, choice: nil, installed: mac())?.name == "TextEdit")
        #expect(PreferredApps.app(for: .editor, choice: nil, installed: mac(plainText: Fake.zed))?.url == Fake.zed)
        #expect(PreferredApps.app(for: .editor, choice: nil, installed: mac(plainText: nil)) == nil, "no app opens text, so there is no editor")
    }

    @Test func aChosenAppIsFoundByItsIdentifierWhereverItIsNow() {
        let choice = AppChoice(bundleIdentifier: "com.mitchellh.ghostty", path: "/Old/Place/Ghostty.app")
        #expect(PreferredApps.app(for: .terminal, choice: choice, installed: mac())?.url == Fake.ghostty)
    }

    @Test func anAppWithoutAnIdentifierIsFoundAtThePathItWasPickedAt() {
        let choice = AppChoice(bundleIdentifier: nil, path: Fake.nova.path)
        #expect(PreferredApps.app(for: .editor, choice: choice, installed: mac(onDisk: [Fake.nova]))?.url == Fake.nova)
    }

    @Test func aChosenAppThatIsGoneGivesWayToTheDefault() {
        let gone = AppChoice(bundleIdentifier: "com.example.gone", path: "/Fake/Applications/Gone.app")
        #expect(PreferredApps.app(for: .terminal, choice: gone, installed: mac())?.url == Fake.terminal)
        #expect(PreferredApps.app(for: .editor, choice: gone, installed: mac())?.url == Fake.textEdit)
    }

    @Test func anAppPickedByHandIsStoredByItsIdentifier() {
        #expect(PreferredApps.choice(forAppAt: Fake.zed, installed: mac()) == AppChoice(bundleIdentifier: "dev.zed.Zed", path: Fake.zed.path))
        #expect(PreferredApps.choice(forAppAt: Fake.nova, installed: mac()) == AppChoice(bundleIdentifier: nil, path: Fake.nova.path))
    }

    @Test func everyRoleThatHasAnAppIsListedWithIt() {
        let ghostty = AppChoice(bundleIdentifier: "com.mitchellh.ghostty", path: Fake.ghostty.path)
        let apps = PreferredApps.apps(choice: { $0 == .terminal ? ghostty : nil }, installed: mac(plainText: nil))
        #expect(apps == [RoleApp(role: .terminal, app: ResolvedApp(url: Fake.ghostty))], "the editor has no app, so it is left out")
    }

    // MARK: What it is handed

    @Test func aTerminalIsHandedTheFolderAFileIsInAndAFolderAsItIs() throws {
        let app = ResolvedApp(url: Fake.ghostty)
        let file = URL(fileURLWithPath: "/Users/me/Projects/floe/README.md", isDirectory: false)
        let folder = URL(fileURLWithPath: "/Users/me/Projects/floe", isDirectory: true)
        let fromFile = try #require(PreferredApps.handoff([file], to: app, role: .terminal, isFolder: isFolder))
        #expect(fromFile.urls.map(\.path) == ["/Users/me/Projects/floe"])
        #expect(fromFile.application == Fake.ghostty)
        #expect(PreferredApps.handoff([folder], to: app, role: .terminal, isFolder: isFolder)?.urls == [folder])
    }

    @Test func filesInOneFolderOpenThatFolderOnce() {
        let app = ResolvedApp(url: Fake.terminal)
        let files = ["a.txt", "b.txt"].map { URL(fileURLWithPath: "/Users/me/Notes/\($0)", isDirectory: false) }
        let other = URL(fileURLWithPath: "/Users/me/Desktop/c.txt", isDirectory: false)
        let handoff = PreferredApps.handoff(files + [other], to: app, role: .terminal, isFolder: isFolder)
        #expect(handoff?.urls.map(\.path) == ["/Users/me/Notes", "/Users/me/Desktop"])
    }

    @Test func anEditorIsHandedFilesAndFoldersAsTheyAre() {
        let app = ResolvedApp(url: Fake.zed)
        let file = URL(fileURLWithPath: "/Users/me/Projects/floe/README.md", isDirectory: false)
        let folder = URL(fileURLWithPath: "/Users/me/Projects/floe", isDirectory: true)
        #expect(PreferredApps.handoff([file, folder], to: app, role: .editor, isFolder: isFolder) == Handoff(urls: [file, folder], application: Fake.zed))
        #expect(PreferredApps.handoff([], to: app, role: .editor, isFolder: isFolder) == nil, "nothing to open is not a handoff")
    }

    // MARK: The picker

    @Test func thePickerOffersTheDefaultAndOnlyTheKnownAppsThatAreInstalled() {
        #expect(PreferredApps.options(for: .terminal, choice: nil, installed: mac()).map(\.title) == ["Terminal", "Ghostty"])
        #expect(PreferredApps.options(for: .editor, choice: nil, installed: mac()).map(\.title) == ["Default for Text Files (TextEdit)", "TextEdit", "Zed"])
        let bare = mac(["com.apple.Terminal": Fake.terminal], plainText: nil)
        #expect(PreferredApps.options(for: .terminal, choice: nil, installed: bare).map(\.title) == ["Terminal"])
        #expect(PreferredApps.options(for: .editor, choice: nil, installed: bare).map(\.title) == ["Default for Text Files"])
    }

    @Test func aKnownAppThatWasChosenIsNotListedTwiceEvenAfterItMoved() {
        let choice = AppChoice(bundleIdentifier: "com.mitchellh.ghostty", path: "/Old/Place/Ghostty.app")
        let options = PreferredApps.options(for: .terminal, choice: choice, installed: mac())
        #expect(options.map(\.id) == [AppOption.defaultID, choice.key])
    }

    @Test func anAppPickedByHandIsListedAndSaysWhenItIsGone() {
        let nova = AppChoice(bundleIdentifier: nil, path: Fake.nova.path)
        #expect(PreferredApps.options(for: .editor, choice: nova, installed: mac(onDisk: [Fake.nova])).last?.title == "Nova")
        let missing = PreferredApps.options(for: .editor, choice: nova, installed: mac()).last
        #expect(missing?.title == "Nova (not installed)")
        #expect(missing?.url == nil)
    }

    @Test func noKnownAppIsListedTwice() {
        for role in AppRole.allCases {
            #expect(Set(role.knownApps).count == role.knownApps.count)
        }
        #expect(!AppRole.terminal.knownApps.contains(AppRole.systemTerminal), "Terminal is the default row already")
    }

    // MARK: Notes as a role

    @Test func theRolesAreTheTerminalTheEditorTheBrowserNotesAndTheClipboardInThatOrder() {
        #expect(AppRole.allCases.map(\.title) == ["Terminal", "Editor", "Browser", "Notes", "Clipboard"])
        #expect(AppRole.opening == [.terminal, .editor], "the browser is handed links, notes text and the clipboard nothing, not files")
    }

    @Test func theNotesRoleOpensNoFilesAndStartsAtAppleNotes() {
        #expect(PreferredApps.app(for: .notes, choice: nil, installed: mac()) == nil)
        #expect(PreferredApps.handoff([URL(fileURLWithPath: "/Fake/a.txt")], to: ResolvedApp(url: Fake.zed), role: .notes, isFolder: isFolder) == nil)
        #expect(AppRole.notes.defaultTitle(appName: nil) == "Apple Notes")
        let settings = AppSettings(defaults: MemoryDefaults())
        #expect(settings.notesApp == .appleNotes)
        #expect(settings.appChoice(for: .notes) == nil, "its choice is the notes app setting")
    }

    @Test func theSettingsSearchFindsEveryRoleUnderPreferredApps() {
        let entries = SearchIndex.generalEntries.filter { $0.section == "Preferred Apps" }.dropLast()
        #expect(entries.map(\.id) == ["general.terminalApp", "general.editorApp", "general.browserApp", "general.notesApp", "general.clipboardApp"])
        #expect(SearchIndex.generalEntries.last { $0.section == "Preferred Apps" }?.id == "general.clearClipboardHistory", "clearing sits under the clipboard's picker")
        #expect(entries.map(\.title) == AppRole.allCases.map(\.title))
        #expect(entries.map(\.descriptionText) == AppRole.allCases.map(\.detail))
    }

    // MARK: Where the actions appear

    @Test func aFileOffersToOpenInTheTerminalAndTheEditorByTheirNames() {
        let host = ActionHost(showHUD: { _ in }, dismiss: {}, preferredApps: [
            RoleApp(role: .terminal, app: ResolvedApp(url: Fake.ghostty)),
            RoleApp(role: .editor, app: ResolvedApp(url: Fake.zed)),
        ])
        let file = URL(fileURLWithPath: "/Fake/Documents/notes.txt")
        let actions = FileActions.preferredAppActions(for: file, host: host)
        #expect(actions.map(\.title) == ["Open in Ghostty", "Open in Zed"])
        #expect(actions.allSatisfy { $0.icon != nil })

        let listed = FileActions.actions(for: file, host: host).map { $0?.title ?? "-" }
        let position = listed.firstIndex(of: "Open in Ghostty") ?? listed.endIndex
        #expect(Array(listed[position...].prefix(3)) == ["Open in Ghostty", "Open in Zed", "Show in Finder"])
    }

    @Test func withoutPreferredAppsAFileHasNoSuchRows() {
        let host = ActionHost(showHUD: { _ in }, dismiss: {})
        #expect(FileActions.preferredAppActions(for: URL(fileURLWithPath: "/Fake/a.txt"), host: host).isEmpty)
    }

    @Test func theSearchOffersTheFinderSelectionForEachRoleByItsAppsName() {
        var context = SearchContext(query: "")
        #expect(FinderSelectionSearchProvider().contribution(for: context).ranked.isEmpty)
        context.preferredApps = [
            RoleApp(role: .terminal, app: ResolvedApp(url: Fake.ghostty)),
            RoleApp(role: .editor, app: ResolvedApp(url: Fake.zed)),
        ]
        let rows = FinderSelectionSearchProvider().contribution(for: context).ranked
        #expect(rows.map(\.id) == ["finder-selection:terminal", "finder-selection:editor"])
        #expect(rows.map(\.title) == ["Open Finder Selection in Ghostty", "Open Finder Selection in Zed"])
        #expect(rows.allSatisfy { $0.kind == "Finder" })
    }

    @Test func theFinderSelectionRowsAnswerToTheirRoleAndToTheAppsName() {
        var context = SearchContext(query: "terminal")
        context.preferredApps = [
            RoleApp(role: .terminal, app: ResolvedApp(url: Fake.ghostty)),
            RoleApp(role: .editor, app: ResolvedApp(url: Fake.zed)),
        ]
        #expect(RootSearch.results(for: context).first?.id == "finder-selection:terminal")
        var named = SearchContext(query: "in zed")
        named.preferredApps = context.preferredApps
        #expect(RootSearch.results(for: named).first?.id == "finder-selection:editor")
    }

    @Test func theModelsRowsAndFileActionsFollowTheChosenApps() {
        let settings = AppSettings(defaults: MemoryDefaults())
        settings.terminalApp = AppChoice(bundleIdentifier: "com.mitchellh.ghostty", path: Fake.ghostty.path)
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []))
        model.resolvedApps.lookup = mac()
        model.query = "finder selection"
        #expect(model.results.prefix(2).map(\.item.title).sorted() == ["Open Finder Selection in Ghostty", "Open Finder Selection in TextEdit"])
        let url = URL(fileURLWithPath: "/Fake/Documents/notes.txt")
        let file = FileResult(url: url, name: "notes.txt", displayPath: url.path, contentType: nil, lastUsed: nil)
        let titles = model.fileSearch.actions(for: file).map { $0?.title ?? "-" }
        #expect(titles.contains("Open in Ghostty") && titles.contains("Open in TextEdit"))
    }
}
