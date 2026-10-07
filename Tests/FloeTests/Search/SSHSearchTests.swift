//
//  SSHSearchTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// A scanner whose only catalog is a list of hosts.
private actor HostScanner: CatalogScanning {
    private var hosts: [SSHHost]

    init(_ hosts: [SSHHost]) {
        self.hosts = hosts
    }

    func scanApps() async -> [AppEntry] {
        []
    }

    func scanCommands(includeRaycast _: Bool) async -> [ExtensionCommand] {
        []
    }

    func scanSSHHosts() async -> [SSHHost] {
        hosts
    }

    func replace(with hosts: [SSHHost]) {
        self.hosts = hosts
    }
}

/// A terminal that is on no Mac.
private nonisolated enum Fake {
    static let terminal = URL(fileURLWithPath: "/Fake/Applications/Hyper.app")
}

@MainActor
struct SSHSearchTests {
    private let scratch: ScratchDefaults
    private let web = SSHHost(alias: "web", hostName: "10.0.0.5", user: "deploy")
    private let database = SSHHost(alias: "db-primary", hostName: "postgres.internal")
    private let bastion = SSHHost(alias: "bastion", user: "ops")

    init() throws {
        scratch = try ScratchDefaults()
    }

    private var hosts: [SSHHost] {
        [web, database, bastion]
    }

    private func context(_ query: String, hosts: [SSHHost]? = nil, _ configure: (inout SearchContext) -> Void = { _ in }) -> SearchContext {
        var context = SearchContext(query: query)
        context.sshHosts = hosts ?? self.hosts
        configure(&context)
        return context
    }

    private func ids(_ results: [RootResult]) -> [String] {
        results.map(\.id)
    }

    /// A model on scratch settings whose only terminal is one that is on no Mac.
    private func makeModel(hosts: [SSHHost], apps: [AppEntry] = [], scanner: (any CatalogScanning)? = nil) -> LauncherModel {
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        let snapshot = CatalogSnapshot(apps: apps, commands: [], sshHosts: hosts)
        let model = LauncherModel(scanner: scanner ?? HostScanner(hosts), settings: settings, usage: UsageStore(defaults: scratch.defaults), snapshot: snapshot, sources: [])
        model.appLookup = AppLookup(
            url: { $0 == AppRole.systemTerminal ? Fake.terminal : nil },
            plainTextApp: { nil },
            exists: { _ in false },
            bundleIdentifier: { _ in nil }
        )
        return model
    }

    // MARK: The row

    @Test func aHostsRowIsItsAliasWithTheAddressBesideItAndTheLabelSSH() {
        let row = RootItem.sshHost(web, terminal: nil)
        #expect(row.title == "web")
        #expect(row.subtitle == "deploy@10.0.0.5")
        #expect(row.kind == "SSH")
        #expect(row.rowLabel == "SSH")
        #expect(row.id == "ssh-host:web")
        #expect(row.settingsKey == "ssh-host:web", "so a host can be given an alias")
        #expect(RootItem.sshHost(web, terminal: ResolvedApp(url: Fake.terminal)).id == row.id, "the terminal is not part of what a host is")
    }

    // MARK: The ordinary search

    @Test func aHostIsFoundByItsAliasItsAddressAndItsUser() {
        #expect(ids(RootSearch.results(for: context("web"))).contains(web.id))
        #expect(ids(RootSearch.results(for: context("postgres"))).contains(database.id))
        #expect(ids(RootSearch.results(for: context("10.0"))).contains(web.id))
        #expect(ids(RootSearch.results(for: context("deploy"))).contains(web.id))
        #expect(!ids(RootSearch.results(for: context("deploy"))).contains(bastion.id))
    }

    @Test func hostsAreNotListedWithoutAQuery() {
        let browsed = RootSearch.results(for: context(""))
        #expect(!browsed.contains { $0.id.hasPrefix("ssh-host:") })
        #expect(SSHHostSearchProvider().contribution(for: context("")).ranked.isEmpty)
        #expect(SSHHostSearchProvider().contribution(for: context("")).searchOnly.count == 3)
    }

    @Test func aFavoriteHostIsListedWithoutAQuery() {
        let browsed = RootSearch.results(for: context("") { $0.favorites = [self.bastion.id] })
        #expect(browsed.first { $0.id == bastion.id }?.section == "Favorites")
        #expect(!ids(browsed).contains(web.id))
    }

    @Test func aHostRanksBesideAnAppWithASimilarName() {
        let webex = AppEntry(name: "Webex", url: URL(fileURLWithPath: "/Fake/Applications/Webex.app"))
        let found = RootSearch.results(for: context("web") { $0.apps = [webex] }).filter { $0.id == web.id || $0.id == RootItem.app(webex).id }
        #expect(ids(found) == [web.id, RootItem.app(webex).id], "the whole name is a better match than the start of one")
        let typed = RootSearch.results(for: context("webe") { $0.apps = [webex] })
        #expect(typed.first?.id == RootItem.app(webex).id)
        #expect(!ids(typed).contains(web.id))
    }

    @Test func anAppUsedOftenStillComesBeforeAHostThatMatchesAsWell() {
        let terminal = AppEntry(name: "Web Inspector", url: URL(fileURLWithPath: "/Fake/Applications/Web Inspector.app"))
        let appID = RootItem.app(terminal).id
        let found = RootSearch.results(for: context("we") {
            $0.apps = [terminal]
            $0.frecency = { $0 == appID ? 10 : 0 }
        })
        #expect(found.first?.id == appID, "usage counts for a host's neighbours as it does everywhere")
        #expect(ids(found).contains(web.id))
    }

    @Test func aHostAnswersToTheAliasTheUserGaveIt() {
        let found = RootSearch.results(for: context("pg") { $0.aliases = [self.database.id: "pg"] })
        #expect(found.first?.id == database.id)
    }

    @Test func withoutHostsNothingIsContributed() {
        let contribution = SSHHostSearchProvider().contribution(for: context("web", hosts: []))
        #expect(contribution.ranked.isEmpty && contribution.searchOnly.isEmpty && contribution.pinned.isEmpty)
        #expect(contribution.sectioned.isEmpty && contribution.appended.isEmpty)
        #expect(RootSearch.scope(in: context("ssh web", hosts: []), scopes: RootSearch.standardScopes()) == nil, "the word is not a scope then")
        #expect(RootSearch.scope(in: context("ssh ", hosts: []), scopes: RootSearch.standardScopes()) == nil)
    }

    @Test func eachRowCarriesTheTerminalItWouldOpenIn() {
        let terminal = ResolvedApp(url: Fake.terminal)
        let rows = context("web") { $0.preferredApps = [RoleApp(role: .editor, app: ResolvedApp(url: URL(fileURLWithPath: "/Fake/Zed.app"))), RoleApp(role: .terminal, app: terminal)] }.sshHostRows
        for row in rows {
            guard case let .sshHost(_, carried) = row else {
                Issue.record("a host's row is a host")
                continue
            }
            #expect(carried == terminal)
        }
        #expect(rows.count == 3)
    }

    // MARK: The scope

    @Test func theKeywordAndSomeTextShowOnlyTheHostsThatMatch() throws {
        let webex = AppEntry(name: "Webex", url: URL(fileURLWithPath: "/Fake/Applications/Webex.app"))
        let context = context("ssh web") { $0.apps = [webex] }
        let match = try #require(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()))
        #expect(match.scope.keyword == "ssh")
        #expect(match.scope.title == "SSH Hosts")
        #expect(match.scope.emptyTitle == "No SSH hosts match")
        #expect(match.text == "web")
        let rows = match.rows(match.scope.results(for: match.text, context: context))
        #expect(ids(rows) == [web.id])
        #expect(rows.allSatisfy { $0.section == "SSH Hosts" })
    }

    @Test func theScopeFindsAHostByItsAddressAndItsUserToo() {
        let scope = SSHSearchScope()
        #expect(scope.results(for: "postgres", context: context("ssh postgres")).map(\.id) == [database.id])
        #expect(scope.results(for: "ops", context: context("ssh ops")).map(\.id) == [bastion.id])
        #expect(scope.results(for: "zzz", context: context("ssh zzz")).isEmpty)
    }

    @Test func theKeywordAndASpaceListEveryHostInTheConfigurationsOrder() throws {
        let context = context("SSH ")
        let match = try #require(RootSearch.scope(in: context, scopes: RootSearch.standardScopes()))
        #expect(match.text.isEmpty)
        #expect(match.scope.results(for: match.text, context: context).map(\.id) == hosts.map(\.id))
    }

    @Test func theKeywordAloneIsAnOrdinarySearch() {
        #expect(RootSearch.scope(in: context("ssh"), scopes: RootSearch.standardScopes()) == nil)
        #expect(RootSearch.scope(in: context("sshfs mount"), scopes: RootSearch.standardScopes()) == nil)
    }

    @Test func theOtherScopesStillNeedSomeText() {
        let scopes = RootSearch.standardScopes()
        #expect(RootSearch.scope(in: context("files "), scopes: scopes) == nil)
        #expect(RootSearch.scope(in: context("clipboard "), scopes: scopes) == nil)
        #expect(RootSearch.scope(in: context("clipboard meeting"), scopes: scopes)?.scope.keyword == "clipboard")
    }

    // MARK: In the launcher

    @Test func theLauncherFindsAHostAndDoesNotListIt() {
        let model = makeModel(hosts: hosts)
        #expect(!model.results.contains { $0.id.hasPrefix("ssh-host:") })
        model.query = "bast"
        #expect(model.results.first?.id == bastion.id)
        guard case let .sshHost(_, terminal) = model.results.first?.item else {
            Issue.record("the first row is the host")
            return
        }
        #expect(terminal?.url == Fake.terminal, "the row knows the terminal, for its icon and for Return")
    }

    @Test func theScopeShowsInTheLauncherUnderItsTitle() {
        let model = makeModel(hosts: hosts)
        model.query = "ssh "
        #expect(model.activeScope?.scope.keyword == "ssh")
        #expect(ids(model.results) == hosts.map(\.id))
        #expect(model.results.allSatisfy { $0.section == "SSH Hosts" })
        model.query = "ssh db"
        #expect(ids(model.results) == [database.id])
    }

    @Test func aHostCanBeAFavoriteAndThenShowsWithoutAQuery() {
        let model = makeModel(hosts: hosts)
        let row = RootItem.sshHost(web, terminal: nil)
        model.toggleFavorite(row)
        #expect(model.isFavorite(row))
        #expect(model.results.first { $0.id == web.id }?.section == "Favorites")
    }

    @Test func theActionsMenuOfAHostConnectsCopiesAndKeepsIt() {
        let model = makeModel(hosts: hosts)
        let row = RootItem.sshHost(web, terminal: nil)
        #expect(model.primaryActionTitle(for: row) == "Connect")
        #expect(model.rootActions(for: row).map { $0?.title ?? "-" } == ["Connect", "-", "Copy Host Name", "Copy SSH Command", "-", "Add to Favorites", "Hide from Search"])
        model.toggleFavorite(row)
        #expect(model.rootActions(for: row).dropLast().last??.title == "Remove from Favorites")
    }

    @Test func returnOnAHostHandsTheAliasToTheTerminalHidesThePanelAndCountsAsAUse() async {
        let model = makeModel(hosts: hosts)
        let (opened, continuation) = AsyncStream.makeStream(of: Handoff.self)
        var hides = 0
        model.hidePanel = { hides += 1 }
        model.sshConnector = SSHConnector(
            bundleIdentifier: { _ in nil },
            takesSSHLinks: { $0 == Fake.terminal },
            systemTerminal: { nil },
            open: { continuation.yield($0) },
            runScript: { _ in .failed }
        )
        model.query = "web"
        let row = model.results.first { $0.id == web.id }?.item
        if let row {
            model.activate(row)
        }
        let handoff = await opened.first { @Sendable _ in true }
        #expect(handoff?.urls.map(\.absoluteString) == ["ssh://web"])
        #expect(handoff?.application == Fake.terminal)
        #expect(hides == 1)
        #expect(model.query.isEmpty, "the launcher is back at its root")
        #expect(model.usage.frecency(of: web.id) > 0)
    }

    @Test func theHostsAreReadAgainWhenAskedAndAnOpenSearchShowsThem() async {
        let scanner = HostScanner([web])
        let model = makeModel(hosts: [], scanner: scanner)
        model.query = "bast"
        #expect(!ids(model.results).contains(bastion.id))
        await scanner.replace(with: [web, bastion])
        await model.reloadSSHHosts().value
        #expect(model.results.first?.id == bastion.id)
        await scanner.replace(with: [])
        await model.reloadSSHHosts().value
        #expect(!ids(model.results).contains(bastion.id), "a host taken out of the configuration is gone")
    }
}
