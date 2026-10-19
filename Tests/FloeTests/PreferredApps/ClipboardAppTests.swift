//
//  ClipboardAppTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Apps that are on no Mac, so no test reads the one it runs on.
private enum Fake {
    static let raycast = URL(fileURLWithPath: "/Fake/Applications/Raycast.app")
    static let clippy = URL(fileURLWithPath: "/Fake/Applications/Clippy.app")
    static let raycastID = "com.raycast.macos"
    static let clippyChoice = AppChoice(bundleIdentifier: "com.example.clippy", path: clippy.path)
    static let raycastChoice = AppChoice(bundleIdentifier: raycastID, path: raycast.path)

    /// A Mac with exactly these apps; a link is answered by the app registered for its scheme.
    static func mac(_ apps: [String: URL] = ["com.example.clippy": clippy, raycastID: raycast], schemes: [String: URL] = ["clippy": clippy]) -> AppLookup {
        AppLookup(
            url: { apps[$0] },
            plainTextApp: { nil },
            exists: { apps.values.contains($0) },
            bundleIdentifier: { url in apps.first { $0.value == url }?.key },
            appForURL: { $0.scheme.flatMap { schemes[$0] } }
        )
    }
}

/// What a test's opener was asked to open, in place of opening it.
private final class Opened {
    var apps: [URL] = []
    var links: [URL] = []
    var linkApps: [URL?] = []
    var hud: [String] = []
    var hides = 0

    var opener: ClipboardOpener {
        ClipboardOpener(
            app: { [self] in apps.append($0) },
            link: { [self] url, app in
                links.append(url)
                linkApps.append(app)
            }
        )
    }
}

@MainActor
struct ClipboardAppTests {
    private let scratch: ScratchDefaults
    private let settings: AppSettings
    private let opened = Opened()

    init() throws {
        scratch = ScratchDefaults()
        settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        settings.clipboardHistoryIsParked = false
    }

    /// A model on scratch settings whose lookups, opener, HUD and panel are the test's own.
    private func makeModel(_ lookup: AppLookup = Fake.mac(), scopes: [any SearchScope] = []) -> LauncherModel {
        let model = LauncherModel(settings: settings, usage: UsageStore(defaults: scratch.defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: scopes, sources: [])
        model.resolvedApps.lookup = lookup
        model.clipboardOpener = opened.opener
        model.panelHost.showHUD = { [opened] in opened.hud.append($0) }
        model.panelHost.hidePanel = { [opened] in opened.hides += 1 }
        return model
    }

    private func destination(_ handler: ClipboardHandler, choice: AppChoice? = nil, link: String = "", on lookup: AppLookup = Fake.mac()) -> ClipboardDestination {
        ClipboardApps.destination(handler: handler, choice: choice, link: link, installed: lookup, parked: false)
    }

    /// Lets what the model queued on the main queue run, without waiting for time to pass.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: The setting

    @Test func theRoleStartsAtFloe() {
        #expect(settings.clipboardHandler == .floe)
        #expect(settings.clipboardApp == nil)
        #expect(settings.clipboardURL.isEmpty)
        #expect(settings.appChoice(for: .clipboard) == nil)
        #expect(settings.clipboardDestination(installed: Fake.mac()) == .floe)
        #expect(settings.recordsClipboardHistory)
    }

    @Test func settingsSavedBeforeTheRoleExistedAreFloeAndKeepTheirSwitch() {
        let old = #"{"commandHotkeys":{},"aliases":{},"disabledExtensions":[],"includeRaycastExtensions":true,"popToRootDelay":30,"clipboardHistoryEnabled":false}"#
        scratch.defaults.set(Data(old.utf8), forKey: "settings")
        let loaded = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(loaded.popToRootDelay == 30, "the old settings were read")
        #expect(loaded.clipboardHandler == .floe)
        #expect(loaded.clipboardApp == nil)
        #expect(loaded.clipboardURL.isEmpty)
        #expect(!loaded.clipboardHistoryEnabled, "the switch keeps what the user set")
    }

    @Test func theChoiceSurvivesASaveAndReachesTheOtherProcess() {
        let launcher = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        settings.clipboardHandler = .app
        settings.clipboardApp = Fake.clippyChoice
        settings.clipboardURL = "clippy://history"
        settings.save()

        launcher.reload()
        #expect(launcher.clipboardHandler == .app)
        #expect(launcher.clipboardApp == Fake.clippyChoice)
        #expect(launcher.clipboardURL == "clippy://history")
        #expect(launcher.appChoice(for: .clipboard) == Fake.clippyChoice)

        let relaunched = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(relaunched.clipboardHandler == .app)
        #expect(relaunched.clipboardApp == Fake.clippyChoice)
        #expect(relaunched.clipboardURL == "clippy://history")
    }

    @Test func theChoiceIsInAnExportAndComesBackFromIt() throws {
        settings.clipboardHandler = .link
        settings.clipboardURL = "clippy://history"
        let exported = try settings.exportedJSON()
        let other = AppSettings(defaults: ScratchDefaults().defaults, savesAfterEdits: false)
        try other.importJSON(exported)
        #expect(other.clipboardHandler == .link)
        #expect(other.clipboardURL == "clippy://history")
    }

    // MARK: Recording

    @Test(arguments: ClipboardHandler.allCases, [true, false])
    func copiesAreSavedOnlyByFloeWithItsSwitchOn(handler: ClipboardHandler, historyEnabled: Bool) {
        let expected = handler == .floe && historyEnabled
        #expect(ClipboardApps.records(handler: handler, historyEnabled: historyEnabled, parked: false) == expected)
        settings.clipboardHandler = handler
        settings.clipboardHistoryEnabled = historyEnabled
        #expect(settings.recordsClipboardHistory == expected)
    }

    @Test func aChoiceThatCannotBeOpenedStillStopsTheRecording() {
        settings.clipboardHandler = .app
        settings.clipboardApp = AppChoice(bundleIdentifier: "com.example.gone", path: "/Fake/Applications/Gone.app")
        #expect(!settings.recordsClipboardHistory)
        settings.clipboardHandler = .link
        settings.clipboardURL = ""
        #expect(!settings.recordsClipboardHistory)
    }

    // MARK: Parked

    @Test(arguments: ClipboardHandler.allCases)
    func parkedFloeSavesNoCopiesAndOffersNoScopeWhateverIsChosen(handler: ClipboardHandler) {
        #expect(!ClipboardApps.records(handler: handler, historyEnabled: true, parked: true))
        let scopes: [any SearchScope] = [FileSearchScope(), ClipboardSearchScope(entries: { [] })]
        #expect(ClipboardApps.scopes(scopes, handler: handler, parked: true).map(\.keyword) == ["files"])
    }

    @Test func parkedTheCommandAsksForAnAppUntilOneIsChosen() {
        let unset = ClipboardApps.destination(handler: .floe, choice: nil, link: "", installed: Fake.mac(), parked: true)
        #expect(unset == .unavailable(app: nil, message: "Choose a clipboard app in Settings"))
        let chosen = ClipboardApps.destination(handler: .app, choice: Fake.clippyChoice, link: "", installed: Fake.mac(), parked: true)
        #expect(chosen.app?.url == Fake.clippy)
    }

    @Test func parkedTheModelNeverOpensFloesOwnHistory() {
        settings.clipboardHistoryIsParked = true
        let model = makeModel()
        model.openClipboardHistory()
        #expect(!model.isShowingClipboardHistory)
        #expect(opened.hud == ["Choose a clipboard app in Settings"])
        #expect(!settings.recordsClipboardHistory)
    }

    // MARK: Where the command goes

    @Test func floeIsItsOwnHistory() {
        #expect(destination(.floe) == .floe)
        #expect(destination(.floe, choice: Fake.clippyChoice, link: "clippy://history") == .floe, "an app or a link kept from before changes nothing")
    }

    @Test func anInstalledAppIsOpenedAsItIs() {
        #expect(destination(.app, choice: Fake.clippyChoice) == .app(ResolvedApp(url: Fake.clippy)))
        let moved = AppChoice(bundleIdentifier: "com.example.clippy", path: "/Old/Place/Clippy.app")
        #expect(destination(.app, choice: moved) == .app(ResolvedApp(url: Fake.clippy)), "found by its identifier wherever it is now")
    }

    @Test func aMissingAppIsNamedAndIsNeverFloe() {
        let gone = AppChoice(bundleIdentifier: "com.example.gone", path: "/Fake/Applications/Gone.app")
        #expect(destination(.app, choice: gone) == .unavailable(app: "Gone", message: "Gone isn't installed"))
        #expect(destination(.app, choice: Fake.raycastChoice, on: Fake.mac([:])) == .unavailable(app: "Raycast", message: "Raycast isn't installed"))
        #expect(destination(.app) == .unavailable(app: nil, message: "Choose a clipboard app in Settings"))
    }

    @Test func anAppWhoseHistoryOpensFromALinkIsOpenedThroughIt() throws {
        let link = try #require(ClipboardApps.links[Fake.raycastID].flatMap(URL.init(string:)))
        #expect(link.scheme == "raycast")
        #expect(destination(.app, choice: Fake.raycastChoice) == .link(link, app: ResolvedApp(url: Fake.raycast)))
        let pickedByHand = AppChoice(bundleIdentifier: nil, path: Fake.raycast.path)
        #expect(destination(.app, choice: pickedByHand) == .link(link, app: ResolvedApp(url: Fake.raycast)), "the identifier is read from the app")
    }

    @Test func aValidLinkIsOpenedAsWritten() throws {
        let url = try #require(URL(string: "clippy://history?show=1"))
        #expect(destination(.link, link: "  clippy://history?show=1 ") == .link(url, app: ResolvedApp(url: Fake.clippy)))
    }

    @Test func anEmptyLinkAsksForOne() {
        let expected = ClipboardDestination.unavailable(app: nil, message: "Set a link for your clipboard app in Settings")
        #expect(destination(.link, link: "") == expected)
        #expect(destination(.link, link: "  \n") == expected)
    }

    @Test(arguments: ["not a link", "history", "://nothing"])
    func aLinkThatIsNotAURLSaysSo(link: String) {
        #expect(ClipboardApps.url(from: link) == nil)
        #expect(destination(.link, link: link) == .unavailable(app: nil, message: "The clipboard link isn't a URL. Change it in Settings"))
    }

    @Test func aLinkNoAppAnswersSaysSo() {
        #expect(destination(.link, link: "nobody://history") == .unavailable(app: nil, message: "No app opens the clipboard link. Change it in Settings"))
    }

    // MARK: The picker

    @Test func thePickerOffersFloeThenTheKnownAppsThatAreInstalled() {
        #expect(PreferredApps.options(for: .clipboard, choice: nil, installed: Fake.mac()).map(\.title) == ["Floe", "Raycast"])
        #expect(PreferredApps.options(for: .clipboard, choice: nil, installed: Fake.mac([:])).map(\.title) == ["Floe"])
        let options = PreferredApps.options(for: .clipboard, choice: Fake.clippyChoice, installed: Fake.mac())
        #expect(options.map(\.title) == ["Floe", "Raycast", "Clippy"])
        #expect(options.first?.choice == nil)
        #expect(PreferredApps.options(for: .clipboard, choice: Fake.clippyChoice, installed: Fake.mac([:])).last?.title == "Clippy (not installed)")
    }

    @Test func everyAppWithALinkIsOfferedByName() {
        #expect(Set(ClipboardApps.links.keys).isSubset(of: AppRole.clipboard.knownApps))
        #expect(ClipboardApps.links.values.allSatisfy { ClipboardApps.url(from: $0) != nil })
    }

    @Test func theClipboardRoleOpensNoFiles() {
        #expect(!AppRole.opening.contains(.clipboard))
        #expect(PreferredApps.app(for: .clipboard, choice: nil, installed: Fake.mac()) == nil)
        #expect(PreferredApps.handoff([URL(fileURLWithPath: "/Fake/a.txt")], to: ResolvedApp(url: Fake.clippy), role: .clipboard, isFolder: { _ in false }) == nil)
    }

    // MARK: The row

    @Test func theRowIsFloesOwnUntilAnotherAppIsChosen() {
        let own = ClipboardApps.row(for: .floe)
        #expect(own.id == RootItem.clipboardHistoryKey)
        #expect(own.rowLabel == "Floe")
        guard case .clipboardHistory = own else {
            Issue.record("Floe's history keeps its own row")
            return
        }
    }

    @Test func theRowOfAnotherAppIsTheSameCommandAndSaysWhereItGoes() throws {
        let app = ClipboardDestination.app(ResolvedApp(url: Fake.clippy))
        let row = ClipboardApps.row(for: app)
        #expect(row.id == RootItem.clipboardHistoryKey, "favorites and usage carry over")
        #expect(row.settingsKey == RootItem.clipboardHistoryKey, "so does its alias")
        #expect(row.title == "Clipboard History")
        #expect(row.rowLabel == "Clippy")
        #expect(app.app?.url == Fake.clippy)

        let url = try #require(URL(string: "clippy://history"))
        #expect(ClipboardApps.row(for: .link(url, app: ResolvedApp(url: Fake.clippy))).rowLabel == "Clippy")
        #expect(ClipboardApps.row(for: .link(url, app: nil)).rowLabel == "Link")
        #expect(ClipboardApps.row(for: .unavailable(app: "Raycast", message: "")).rowLabel == "Raycast")
        #expect(ClipboardApps.row(for: .unavailable(app: nil, message: "")).rowLabel == "Not Set Up")
        #expect(ClipboardDestination.unavailable(app: "Raycast", message: "").app == nil, "an app that is gone has no icon to show")
    }

    @Test func theSearchListsOneClipboardRowWhicheverAppKeepsTheHistory() {
        var context = SearchContext(query: "")
        let own = CatalogSearchProvider().contribution(for: context).ranked.filter { $0.id == RootItem.clipboardHistoryKey }
        #expect(own.map(\.rowLabel) == ["Floe"])
        context.clipboardDestination = .app(ResolvedApp(url: Fake.clippy))
        let handed = CatalogSearchProvider().contribution(for: context).ranked.filter { $0.id == RootItem.clipboardHistoryKey }
        #expect(handed.map(\.rowLabel) == ["Clippy"])
    }

    // MARK: The scope

    @Test(arguments: ClipboardHandler.allCases)
    func theClipboardScopeIsOfferedOnlyWhileFloeKeepsTheHistory(handler: ClipboardHandler) {
        let scopes: [any SearchScope] = [FileSearchScope(), ClipboardSearchScope(entries: { [] }), MenuBarSearchScope()]
        let offered = ClipboardApps.scopes(scopes, handler: handler, parked: false).map(\.keyword)
        #expect(offered == (handler == .floe ? ["files", "clipboard", "menu"] : ["files", "menu"]))
    }

    @Test func theModelSearchesTheClipboardScopeOnlyForFloe() {
        let model = makeModel(scopes: [ClipboardSearchScope(entries: { [] })])
        model.query = "clipboard meeting"
        #expect(model.activeScope?.scope.keyword == "clipboard")

        model.query = ""
        settings.clipboardHandler = .app
        settings.clipboardApp = Fake.clippyChoice
        model.query = "clipboard meeting"
        #expect(model.activeScope == nil, "the words are an ordinary search now")
        #expect(!model.results.contains { $0.item.isScopeResult })
    }

    // MARK: Running the command

    @Test func withFloeTheCommandShowsFloesHistory() {
        let model = makeModel()
        model.activate(.clipboardHistory)
        #expect(model.isShowingClipboardHistory)
        #expect(opened.apps.isEmpty && opened.links.isEmpty && opened.hud.isEmpty)
    }

    @Test func withAnAppTheCommandOpensItAndHidesTheLauncher() {
        let model = makeModel()
        settings.clipboardHandler = .app
        settings.clipboardApp = Fake.clippyChoice
        model.query = "clipboard"
        let row = model.results.first?.item
        #expect(row?.rowLabel == "Clippy")
        model.activate(row ?? .clipboardHistory)
        #expect(opened.apps == [Fake.clippy])
        #expect(opened.hides == 1)
        #expect(!model.isShowingClipboardHistory)
        #expect(model.query.isEmpty)
        #expect(opened.hud.isEmpty)
    }

    @Test func aStaleRowOfFloesOwnStillGoesToTheChosenApp() {
        let model = makeModel()
        settings.clipboardHandler = .app
        settings.clipboardApp = Fake.clippyChoice
        model.activate(.clipboardHistory)
        model.openClipboardHistory()
        #expect(opened.apps == [Fake.clippy, Fake.clippy])
        #expect(!model.isShowingClipboardHistory, "nothing leads to Floe's history while another app keeps it")
    }

    @Test func withAKnownAppTheCommandOpensItsLinkInThatApp() {
        let model = makeModel()
        settings.clipboardHandler = .app
        settings.clipboardApp = Fake.raycastChoice
        model.openClipboardHistory()
        #expect(opened.links.map(\.absoluteString) == ["raycast://extensions/raycast/clipboard-history/clipboard-history"])
        #expect(opened.linkApps == [Fake.raycast])
        #expect(opened.apps.isEmpty)
    }

    @Test func withALinkTheCommandOpensTheLink() {
        let model = makeModel()
        settings.clipboardHandler = .link
        settings.clipboardURL = "clippy://history"
        model.openClipboardHistory()
        #expect(opened.links.map(\.absoluteString) == ["clippy://history"])
        #expect(opened.linkApps == [Fake.clippy])
        #expect(opened.hides == 1)
    }

    @Test func aMissingAppIsSaidInTheHUDAndFloesHistoryStaysShut() {
        let model = makeModel(Fake.mac([:]))
        settings.clipboardHandler = .app
        settings.clipboardApp = Fake.raycastChoice
        model.query = "clipboard"
        #expect(model.results.first?.item.rowLabel == "Raycast")
        model.openClipboardHistory()
        #expect(opened.hud == ["Raycast isn't installed"])
        #expect(opened.apps.isEmpty && opened.links.isEmpty)
        #expect(!model.isShowingClipboardHistory)
        #expect(!settings.recordsClipboardHistory, "the choice is still not Floe")
    }

    @Test func aLinkThatIsEmptyOrNotAURLIsSaidInTheHUD() {
        let model = makeModel()
        settings.clipboardHandler = .link
        model.openClipboardHistory()
        settings.clipboardURL = "not a link"
        model.openClipboardHistory()
        #expect(opened.hud == ["Set a link for your clipboard app in Settings", "The clipboard link isn't a URL. Change it in Settings"])
        #expect(opened.links.isEmpty)
        #expect(!model.isShowingClipboardHistory)
    }

    @Test func choosingAnotherAppInSettingsClosesFloesHistoryAndRedrawsTheRow() async {
        let model = makeModel()
        let following = model.followClipboardRole()
        model.openClipboardHistory()
        #expect(model.isShowingClipboardHistory)

        settings.clipboardApp = Fake.clippyChoice
        settings.clipboardHandler = .app
        await drainMainQueue()
        #expect(!model.isShowingClipboardHistory)
        #expect(model.results.first { $0.item.id == RootItem.clipboardHistoryKey }?.item.rowLabel == "Clippy")

        settings.clipboardHandler = .floe
        await drainMainQueue()
        #expect(model.results.first { $0.item.id == RootItem.clipboardHistoryKey }?.item.rowLabel == "Floe")
        following.cancel()
    }

    // MARK: Settings

    @Test func theSettingsSearchFindsTheRoleAndClearing() {
        let entries = SearchIndex.applicationsEntries.filter { SearchIndex.clipboardEntries.map(\.id).contains($0.id) }
        #expect(entries.map(\.id) == ["applications.clipboardApp", "applications.clearClipboardHistory"])
        #expect(entries.map(\.section) == ["Preferred Apps", "Preferred Apps"])
        #expect(entries.first?.title == AppRole.clipboard.title)
        #expect(entries.first?.descriptionText == AppRole.clipboard.detail)
        #expect(AppRole.clipboard.detail == "Opens from Clipboard History in the search. With Off or another app, Floe saves no new copies and keeps the ones it has.")
    }
}
