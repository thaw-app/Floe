//
//  BrowserTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Browsers that are on no Mac, so no test reads the one it runs on.
private enum Fake {
    static let safari = URL(fileURLWithPath: "/Fake/System/Safari.app")
    static let arc = URL(fileURLWithPath: "/Fake/Applications/Arc.app")
    static let zen = URL(fileURLWithPath: "/Fake/Applications/Zen.app")
    static let chat = URL(fileURLWithPath: "/Fake/Applications/Chat.app")
    static let apps = ["com.apple.Safari": safari, "company.thebrowser.Browser": arc, "app.zen-browser.zen": zen, "com.example.chat": chat]
    static let zenChoice = AppChoice(bundleIdentifier: "app.zen-browser.zen", path: zen.path)
    static let goneChoice = AppChoice(bundleIdentifier: "com.example.orion", path: "/Fake/Applications/Orion.app")

    /// A Mac with exactly these apps: the system lists `browsers`, and `standard` opens web links.
    static func mac(_ apps: [String: URL] = apps, browsers: [URL] = [zen, safari, arc], standard: URL? = safari) -> AppLookup {
        AppLookup(
            url: { apps[$0] },
            plainTextApp: { nil },
            exists: { apps.values.contains($0) },
            bundleIdentifier: { url in apps.first { $0.value == url }?.key },
            appForURL: { Browsers.isWebLink($0) ? standard : nil },
            browsers: { browsers }
        )
    }
}

/// What a test's opener was asked to open, in place of opening it. Only the main actor touches it.
private final nonisolated class Opened: @unchecked Sendable {
    var links: [String] = []
    var apps: [URL?] = []
    var hud: [String] = []
    var hides = 0

    var opener: LinkOpener {
        LinkOpener { [self] url, app in
            links.append(url.absoluteString)
            apps.append(app)
        }
    }
}

@MainActor
struct BrowserTests {
    private let scratch: ScratchDefaults
    private let settings: AppSettings
    private let opened = Opened()

    init() throws {
        scratch = ScratchDefaults()
        settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
    }

    /// A model on scratch settings whose lookups, opener, HUD and panel are the test's own.
    private func makeModel(_ lookup: AppLookup = Fake.mac()) -> LauncherModel {
        let model = LauncherModel(settings: settings, usage: UsageStore(defaults: scratch.defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        model.resolvedApps.lookup = lookup
        model.linkOpener = opened.opener
        model.panelHost.showHUD = { [opened] in opened.hud.append($0) }
        model.panelHost.hidePanel = { [opened] in opened.hides += 1 }
        return model
    }

    private func link(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    private func titles(_ actions: [ItemAction?]) -> [String] {
        actions.map { $0?.title ?? "-" }
    }

    // MARK: The role

    @Test func theBrowserRoleStartsAtWhateverTheSystemOpensLinksWith() {
        #expect(settings.browserApp == nil)
        #expect(settings.appChoice(for: .browser) == nil)
        #expect(AppRole.browser.title == "Browser")
        #expect(AppRole.browser.defaultTitle(appName: "Safari") == "Default Browser (Safari)")
        #expect(AppRole.browser.defaultTitle(appName: nil) == "Default Browser")
        #expect(PreferredApps.app(for: .browser, choice: nil, installed: Fake.mac())?.url == Fake.safari)
        #expect(PreferredApps.app(for: .browser, choice: nil, installed: Fake.mac(standard: nil)) == nil)
        #expect(!AppRole.opening.contains(.browser), "a browser is handed links, not the Finder selection")
        let file = URL(fileURLWithPath: "/Fake/a.html")
        #expect(PreferredApps.handoff([file], to: ResolvedApp(url: Fake.zen), role: .browser, isFolder: { _ in false }) == nil)
    }

    @Test func settingsStoredBeforeTheRoleLoadUnchangedAndTheChoiceIsKept() {
        let before = #"{"popToRootDelay":30,"terminalApp":{"bundleIdentifier":"com.mitchellh.ghostty","path":"/Applications/Ghostty.app"}}"#
        scratch.defaults.set(Data(before.utf8), forKey: "settings")
        let loaded = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(loaded.browserApp == nil)
        #expect(loaded.popToRootDelay == 30)
        #expect(loaded.terminalApp == AppChoice(bundleIdentifier: "com.mitchellh.ghostty", path: "/Applications/Ghostty.app"))

        loaded.browserApp = Fake.zenChoice
        loaded.save()
        let again = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(again.browserApp == Fake.zenChoice)
        #expect(again.terminalApp == loaded.terminalApp && again.popToRootDelay == 30)
        #expect(again.appChoice(for: .browser) == Fake.zenChoice)
    }

    // MARK: The picker

    @Test func aBrowserOpensBothKindsOfLinkAndHTMLFiles() {
        let secure = [Fake.safari, Fake.chat, Fake.zen, Fake.arc]
        #expect(Browsers.browsers(secure: secure, plain: secure, pages: [Fake.arc, Fake.safari, Fake.zen]) == [Fake.safari, Fake.zen, Fake.arc], "a chat app that takes links is no browser")
        #expect(Browsers.browsers(secure: secure, plain: [Fake.safari], pages: secure) == [Fake.safari])
        #expect(Browsers.browsers(secure: [], plain: secure, pages: secure).isEmpty)
    }

    @Test func chatGPTIsLeftOutByNameEvenIfItPassesForABrowser() {
        let chat = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let ids = [chat: "com.openai.codex", Fake.safari: "com.apple.Safari"]
        #expect(Browsers.withoutLinkHandlers([Fake.safari, chat, Fake.zen]) { ids[$0] } == [Fake.safari, Fake.zen])
    }

    @Test func thePickerListsTheDefaultThenTheSystemsBrowsersDefaultFirstAndTheRestByName() {
        let options = PreferredApps.options(for: .browser, choice: nil, installed: Fake.mac())
        #expect(options.map(\.title) == ["Default Browser (Safari)", "Safari", "Arc", "Zen"])
        #expect(options.map(\.id) == [AppOption.defaultID, "com.apple.Safari", "company.thebrowser.Browser", "app.zen-browser.zen"])
        #expect(options.map(\.url) == [Fake.safari, Fake.safari, Fake.arc, Fake.zen])

        let other = PreferredApps.options(for: .browser, choice: nil, installed: Fake.mac(standard: Fake.zen))
        #expect(other.map(\.title) == ["Default Browser (Zen)", "Zen", "Arc", "Safari"])
    }

    @Test func aMacWithNoBrowserStillHasTheDefaultRow() {
        let bare = Fake.mac([:], browsers: [], standard: nil)
        #expect(PreferredApps.options(for: .browser, choice: nil, installed: bare).map(\.title) == ["Default Browser"])
    }

    @Test func aDefaultThatIsNotABrowserIsNamedOnlyInTheDefaultRow() {
        let options = PreferredApps.options(for: .browser, choice: nil, installed: Fake.mac(standard: Fake.chat))
        #expect(options.map(\.title) == ["Default Browser (Chat)", "Arc", "Safari", "Zen"])
    }

    @Test func aChosenBrowserIsListedOnceAndOneThatIsGoneSaysSo() {
        let chosen = PreferredApps.options(for: .browser, choice: Fake.zenChoice, installed: Fake.mac())
        #expect(chosen.map(\.title) == ["Default Browser (Safari)", "Safari", "Arc", "Zen"])

        let gone = PreferredApps.options(for: .browser, choice: Fake.goneChoice, installed: Fake.mac())
        #expect(gone.map(\.title) == ["Default Browser (Safari)", "Safari", "Arc", "Zen", "Orion (not installed)"])
        #expect(gone.last?.url == nil)
    }

    @Test func anAppPickedWithChooseIsListedAfterTheBrowsers() {
        let choice = PreferredApps.choice(forAppAt: Fake.chat, installed: Fake.mac())
        #expect(choice == AppChoice(bundleIdentifier: "com.example.chat", path: Fake.chat.path))
        let options = PreferredApps.options(for: .browser, choice: choice, installed: Fake.mac())
        #expect(options.map(\.title) == ["Default Browser (Safari)", "Safari", "Arc", "Zen", "Chat"])
        #expect(Browsers.current(choice: choice, installed: Fake.mac())?.url == Fake.chat)
    }

    @Test func twoCopiesOfOneBrowserAreOneRow() {
        let copy = URL(fileURLWithPath: "/Fake/Downloads/Zen.app")
        var apps = Fake.apps
        apps["app.zen-browser.zen"] = Fake.zen
        let lookup = AppLookup(
            url: { apps[$0] },
            plainTextApp: { nil },
            exists: { _ in true },
            bundleIdentifier: { $0.lastPathComponent == "Zen.app" ? "app.zen-browser.zen" : nil },
            browsers: { [Fake.zen, copy] }
        )
        #expect(Browsers.options(installed: lookup).map(\.title) == ["Zen"])
    }

    // MARK: Where a link opens

    @Test func onDefaultALinkOpensThroughTheSystem() throws {
        let url = try link("https://github.com/thaw-app")
        #expect(Browsers.destination(for: url, choice: nil, installed: Fake.mac()) == .system)
        #expect(Browsers.open(url, choice: nil, installed: Fake.mac(), opener: opened.opener) == nil)
        #expect(opened.links == ["https://github.com/thaw-app"])
        #expect(opened.apps == [nil])
    }

    @Test func withABrowserChosenAWebLinkOpensInIt() throws {
        for text in ["https://github.com/thaw-app", "http://localhost:3000", "HTTPS://EXAMPLE.COM"] {
            #expect(try Browsers.open(link(text), choice: Fake.zenChoice, installed: Fake.mac(), opener: opened.opener) == nil)
        }
        #expect(opened.links.count == 3)
        #expect(opened.apps == [Fake.zen, Fake.zen, Fake.zen])
    }

    @Test func aBrowserThatIsGoneGivesWayToTheSystemAndSaysSo() throws {
        let url = try link("https://github.com/thaw-app")
        #expect(Browsers.destination(for: url, choice: Fake.goneChoice, installed: Fake.mac()) == .systemInstead(of: "Orion"))
        #expect(Browsers.open(url, choice: Fake.goneChoice, installed: Fake.mac(), opener: opened.opener) == "Orion isn't installed. Opened in Safari")
        let unnamed = Browsers.open(url, choice: Fake.goneChoice, installed: Fake.mac(standard: nil), opener: opened.opener)
        #expect(unnamed == "Orion isn't installed. Opened in the default browser")
        #expect(opened.links == [url.absoluteString, url.absoluteString], "the link opens all the same")
        #expect(opened.apps == [nil, nil])
        #expect(Browsers.current(choice: Fake.goneChoice, installed: Fake.mac())?.url == Fake.safari)
    }

    @Test(arguments: ["mailto:someone@example.com", "raycast://extensions/raycast/clipboard-history", "maps://?q=coffee", "file:///Users/me/a.html", "x-apple.systempreferences:com.apple.preference.security", "thaw://settings"])
    func aLinkThatIsNoWebPageNeverGoesToTheBrowser(text: String) throws {
        let url = try link(text)
        for choice in [Fake.zenChoice, Fake.goneChoice] {
            #expect(Browsers.destination(for: url, choice: choice, installed: Fake.mac()) == .system)
            #expect(Browsers.open(url, choice: choice, installed: Fake.mac(), opener: opened.opener) == nil)
        }
        #expect(opened.apps == [nil, nil])
        #expect(!Browsers.isWebLink(url))
    }

    @Test func aLinkClickedInAViewIsLeftToTheSystemUnlessABrowserIsChosen() throws {
        let url = try link("https://github.com/thaw-app/Floe")
        let note: (String) -> Void = { [opened] in opened.hud.append($0) }
        #expect(!Browsers.openFromView(url, choice: nil, installed: Fake.mac(), opener: opened.opener, notify: note))
        #expect(try !Browsers.openFromView(link("mailto:a@example.com"), choice: Fake.zenChoice, installed: Fake.mac(), opener: opened.opener, notify: note))
        #expect(opened.links.isEmpty, "the view's own way of opening is used, as before")

        #expect(Browsers.openFromView(url, choice: Fake.zenChoice, installed: Fake.mac(), opener: opened.opener, notify: note))
        #expect(opened.apps == [Fake.zen])
        #expect(Browsers.openFromView(url, choice: Fake.goneChoice, installed: Fake.mac(), opener: opened.opener, notify: note))
        #expect(opened.apps == [Fake.zen, nil])
        #expect(opened.hud == ["Orion isn't installed. Opened in Safari"])
    }

    // MARK: What the launcher opens

    @Test func aTypedAddressOpensInTheChosenBrowser() throws {
        let model = makeModel()
        let row = try RootItem.webAddress(#require(WebAddress(typed: "github.com/thaw-app")))
        model.activate(row)
        settings.browserApp = Fake.zenChoice
        model.activate(row)
        #expect(opened.links == ["https://github.com/thaw-app", "https://github.com/thaw-app"])
        #expect(opened.apps == [nil, Fake.zen])
        #expect(opened.hides == 2)
        #expect(opened.hud.isEmpty)
    }

    @Test func aQuicklinkAndAFallbackSearchOpenInTheChosenBrowser() {
        let model = makeModel()
        settings.browserApp = Fake.zenChoice
        let google = Quicklink(name: "Google", keyword: "g", url: "https://www.google.com/search?q={query}", isFallback: true)
        model.activate(.quicklink(google, queryText: "swift", fallback: false, keywordSearch: true))
        model.activate(.quicklink(google, queryText: "floe", fallback: true, keywordSearch: false))
        #expect(opened.links == ["https://www.google.com/search?q=swift", "https://www.google.com/search?q=floe"])
        #expect(opened.apps == [Fake.zen, Fake.zen])
        #expect(opened.hides == 2)
    }

    @Test func aQuicklinkToAnAppsOwnSchemeStaysWithTheSystem() {
        let model = makeModel()
        settings.browserApp = Fake.zenChoice
        let maps = Quicklink(name: "Apple Maps", keyword: "maps", url: "maps://?q={query}")
        let mail = Quicklink(name: "Mail", keyword: "mail", url: "mailto:someone@example.com")
        model.activate(.quicklink(maps, queryText: "coffee", fallback: false, keywordSearch: true))
        model.activate(.quicklink(mail, queryText: "", fallback: false, keywordSearch: false))
        #expect(opened.links == ["maps://?q=coffee", "mailto:someone@example.com"])
        #expect(opened.apps == [nil, nil])
    }

    @Test func aBrowserThatIsGoneIsSaidInTheHUDAndTheLinkStillOpens() throws {
        let model = makeModel()
        settings.browserApp = Fake.goneChoice
        try model.activate(.webAddress(#require(WebAddress(typed: "github.com"))))
        #expect(opened.links == ["https://github.com"])
        #expect(opened.apps == [nil])
        #expect(opened.hud == ["Orion isn't installed. Opened in Safari"])
    }

    @Test func anExtensionsOpenUsesTheChosenBrowserUnlessItNamesAnApp() {
        let model = makeModel()
        settings.browserApp = Fake.zenChoice
        model.runner.handleBackgroundMessage(["type": "open", "target": "https://example.com/docs"])
        model.runner.handleBackgroundMessage(["type": "open", "target": "https://example.com/docs", "application": Fake.arc.path])
        model.runner.handleBackgroundMessage(["type": "open", "target": "/Fake/notes.txt"])
        model.runner.handleBackgroundMessage(["type": "open", "target": "raycast://extensions/a/b"])
        #expect(opened.links == ["https://example.com/docs", "https://example.com/docs", "file:///Fake/notes.txt", "raycast://extensions/a/b"])
        #expect(opened.apps == [Fake.zen, Fake.arc, nil, nil], "the extension's own choice of app is honoured")
    }

    @Test func onDefaultAnExtensionsOpenGoesThroughTheSystem() {
        let model = makeModel()
        model.runner.handleBackgroundMessage(["type": "open", "target": "https://example.com/docs"])
        #expect(opened.apps == [nil])
    }

    // MARK: The Actions menu

    @Test func aWebAddressOffersItsBrowserThenTheOthersThenCopyAddress() throws {
        let model = makeModel()
        let row = try RootItem.webAddress(#require(WebAddress(typed: "github.com/thaw-app")))
        #expect(model.primaryActionTitle(for: row) == "Open in Safari")
        let actions = model.rootActions(for: row)
        #expect(titles(actions) == ["Open in Safari", "Open With", "Copy Address"], "no favorite toggle: the row is gone next time")
        #expect(actions[1]?.children.map(\.title) == ["Arc", "Zen"])

        settings.browserApp = Fake.zenChoice
        let chosen = model.rootActions(for: row)
        #expect(titles(chosen) == ["Open in Zen", "Open With", "Copy Address"])
        #expect(chosen[1]?.children.map(\.title) == ["Safari (default)", "Arc"])

        chosen[1]?.children.last?.run()
        #expect(opened.links == ["https://github.com/thaw-app"])
        #expect(opened.apps == [Fake.arc])
        #expect(opened.hides == 1, "opening in another browser closes the panel, as Open With does for a file")

        chosen[0]?.run()
        #expect(opened.apps == [Fake.arc, Fake.zen])
    }

    @Test func aBrowserThatIsGoneLeavesTheMenuOnTheDefault() throws {
        let model = makeModel()
        settings.browserApp = Fake.goneChoice
        let row = try RootItem.webAddress(#require(WebAddress(typed: "github.com")))
        let actions = model.rootActions(for: row)
        #expect(titles(actions) == ["Open in Safari", "Open With", "Copy Address"])
        #expect(actions[1]?.children.map(\.title) == ["Arc", "Zen"])
    }

    @Test func withOneBrowserOrNoneThereIsNoOpenWith() throws {
        let row = try RootItem.webAddress(#require(WebAddress(typed: "github.com")))
        let one = makeModel(Fake.mac(browsers: [Fake.safari]))
        #expect(titles(one.rootActions(for: row)) == ["Open in Safari", "Copy Address"])
        let none = makeModel(Fake.mac([:], browsers: [], standard: nil))
        #expect(none.primaryActionTitle(for: row) == "Open")
        #expect(titles(none.rootActions(for: row)) == ["Open", "Copy Address"])
    }

    @Test func copyAddressCopiesTheWholeURLThatWouldOpen() throws {
        let address = try #require(WebAddress(typed: "github.com/thaw-app"))
        var copied: [String] = []
        let host = ActionHost(showHUD: { [opened] in opened.hud.append($0) }, dismiss: { [opened] in opened.hides += 1 })
        let action = LinkActions.copyAddress(address.url, host: host) { copied.append($0) }
        action.run()
        #expect(action.title == "Copy Address")
        #expect(copied == ["https://github.com/thaw-app"])
        #expect(opened.hud == ["Copied Address"])
        #expect(opened.hides == 0)
    }

    @Test func aQuicklinkToAWebPageOffersOpenWithAndOneToAnAppDoesNot() {
        let model = makeModel()
        let google = Quicklink(name: "Google", keyword: "g", url: "https://www.google.com/search?q={query}", isFallback: true)
        let maps = Quicklink(name: "Apple Maps", keyword: "maps", url: "maps://?q={query}")
        let web = model.rootActions(for: .quicklink(google, queryText: "swift", fallback: true, keywordSearch: false))
        #expect(titles(web) == ["Open", "Open With"])
        #expect(web[1]?.children.map(\.title) == ["Arc", "Zen"])
        web[1]?.children.first?.run()
        #expect(opened.links == ["https://www.google.com/search?q=swift"])
        #expect(opened.apps == [Fake.arc])
        #expect(titles(model.rootActions(for: .quicklink(maps, queryText: "coffee", fallback: false, keywordSearch: true))) == ["Open"])
    }

    // MARK: Settings

    @Test func theSettingsSearchFindsTheBrowserRole() {
        let entries = SearchIndex.generalEntries.filter { $0.id == "general.browserApp" }
        #expect(entries.count == 1)
        #expect(entries.first?.title == "Browser")
        #expect(entries.first?.section == "Preferred Apps")
        #expect(entries.first?.descriptionText == AppRole.browser.detail)
        #expect(entries.first?.keywords.contains("default browser") == true)
        #expect(SearchIndex.staticEntries.filter { $0.id == "general.browserApp" }.count == 1)
    }
}
