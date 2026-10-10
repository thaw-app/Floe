//
//  ExtensionStoreTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ExtensionStoreTests {
    @Test func aManifestBecomesTheStoreDetails() {
        let details = ExtensionStore.parseDetails(name: "weather-test", manifest: [
            "title": "Weather",
            "description": "Forecasts",
            "author": ["name": "someone"],
            "icon": "assets/weather icon.png",
            "commands": [["name": "forecast", "title": "Forecast"], ["name": "refresh", "mode": "no-view"], ["title": "Nameless"]],
        ])
        #expect(details.title == "Weather")
        #expect(details.author == "someone")
        #expect(details.commands.map(\.name) == ["forecast", "refresh"])
        #expect(details.commands.map(\.mode) == ["view", "no-view"])
    }

    @Test func remoteIconNamesAreEncoded() {
        let url = ExtensionStore.iconURL(for: "weather-test-not-installed", icon: "assets/weather icon.png")
        #expect(url?.absoluteString.hasSuffix("/weather-test-not-installed/assets/weather%20icon.png") == true)
    }

    @Test(arguments: ["icon:Star", "https://example.com/i.png", "data:image/png;base64,AA", ""])
    func iconsThatAreNotFilesInTheRepositoryHaveNoURL(icon: String) {
        #expect(ExtensionStore.iconURL(for: "weather-test", icon: icon) == nil)
    }

    @Test func aToolThatSucceedsHandsBackWhatItPrinted() async throws {
        let output = try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", "pwd; echo note >&2"], workingDirectory: URL(fileURLWithPath: "/usr"), context: "Listing failed")
        #expect(output.stdout == "/usr\n")
        #expect(output.stderr == "note\n")
    }

    @Test func aToolThatFailsReportsItsLastErrorLine() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", "echo out; echo first >&2; echo last >&2; echo >&2; exit 3"], context: "Clone failed")
        }
        #expect(failure?.message == "Clone failed: last")
    }

    @Test func aToolThatFailsQuietlyOnStderrReportsItsOutput() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", "echo said; exit 1"], context: "Clone failed")
        }
        #expect(failure?.message == "Clone failed: said")
    }

    @Test func aToolThatCannotStartFailsWithItsContext() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/nonexistent/floe-tool", arguments: [], context: "Bun install failed")
        }
        #expect(failure?.message.hasPrefix("Bun install failed: ") == true)
    }

    @Test func aManifestWithOnlyCommandNamesFallsBackToThem() {
        let details = ExtensionStore.parseDetails(name: "bare-test", manifest: ["commands": [["name": "run", "description": "Runs it"]]])
        #expect(details.name == "bare-test")
        #expect(details.title == "bare-test")
        #expect(details.description == nil)
        #expect(details.author == nil)
        #expect(details.iconURL == nil)
        #expect(details.commands == [StoreCommand(name: "run", title: "run", description: "Runs it", mode: "view")])
    }

    @Test func aManifestWithoutCommandsListsNone() {
        #expect(ExtensionStore.parseDetails(name: "bare-test", manifest: [:]).commands.isEmpty)
        #expect(ExtensionStore.parseDetails(name: "bare-test", manifest: ["commands": "forecast"]).commands.isEmpty)
    }

    @Test func theAuthorIsReadFromWhicheverShapeTheManifestUses() {
        #expect(ExtensionStore.parseDetails(name: "a", manifest: ["author": "someone", "owner": "a-team"]).author == "someone")
        #expect(ExtensionStore.parseDetails(name: "a", manifest: ["author": ["name": "someone"], "owner": "a-team"]).author == "someone")
        #expect(ExtensionStore.parseDetails(name: "a", manifest: ["owner": "a-team"]).author == "a-team")
        #expect(ExtensionStore.parseDetails(name: "a", manifest: ["author": ["email": "someone@example.com"], "owner": "a-team"]).author == nil, "an author without a name hides the owner")
        #expect(ExtensionStore.parseDetails(name: "a", manifest: ["author": 7]).author == nil)
    }

    @Test func theDetailsCarryTheIconsRemoteAddress() {
        let details = ExtensionStore.parseDetails(name: "weather-test-not-installed", manifest: ["description": "Forecasts", "icon": "icon.png"])
        #expect(details.description == "Forecasts")
        #expect(details.iconURL?.absoluteString == "https://raw.githubusercontent.com/raycast/extensions/main/extensions/weather-test-not-installed/assets/icon.png")
    }

    @Test func anIconInASubfolderIsFetchedByItsFileName() {
        let url = ExtensionStore.iconURL(for: "weather-test-not-installed", icon: "assets/dark/icon@2x.png")
        #expect(url?.absoluteString == "https://raw.githubusercontent.com/raycast/extensions/main/extensions/weather-test-not-installed/assets/icon@2x.png")
    }

    @Test func anIconThatIsNotTextHasNoURL() {
        #expect(ExtensionStore.iconURL(for: "weather-test", icon: nil) == nil)
        #expect(ExtensionStore.iconURL(for: "weather-test", icon: ["light": "a.png", "dark": "b.png"]) == nil)
    }

    @Test func listingsAndCommandsAreIdentifiedByName() {
        #expect(StoreListing(name: "weather").id == "weather")
        #expect(StoreCommand(name: "forecast", title: "Forecast", description: nil, mode: "view").id == "forecast")
    }

    @Test func aToolThatOnlyPrintsLeavesStderrEmpty() async throws {
        let output = try await ExtensionStore.runTool(executable: "/bin/echo", arguments: ["abc123"], context: "Could not read the repository commit")
        #expect(output.stdout == "abc123\n")
        #expect(output.stderr.isEmpty)
    }

    @Test(arguments: ["exit 1", "echo ' ' >&2; echo; exit 1"])
    func aToolThatFailsWithoutSayingWhyReportsAnUnknownError(script: String) async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", script], context: "Checkout failed")
        }
        #expect(failure?.message == "Checkout failed: Unknown error")
    }

    @Test func aToolThatFailsReportsOnlyTheLastOfSeveralOutputLines() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", "printf 'one\\ntwo\\n\\n'; exit 2"], context: "Bun install failed")
        }
        #expect(failure?.message == "Bun install failed: two")
    }

    @Test func aToolThatPrintsMoreThanIsKeptFailsWithItsContext() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/usr/bin/head", arguments: ["-c", "5000000", "/dev/zero"], context: "Clone failed")
        }
        #expect(failure?.message.hasPrefix("Clone failed: ") == true)
        #expect(failure?.message != "Clone failed: Unknown error")
    }

    @Test func whatIsRecordedAtInstallIsWhatAnUpdateCheckCompares() {
        let answer = Data(#"[{"sha":"folder-newest","commit":{}},{"sha":"folder-older"}]"#.utf8)
        #expect(ExtensionStore.newestCommit(in: answer) == "folder-newest")
        #expect(ExtensionStore.newestCommit(in: Data("[]".utf8)) == nil)
        #expect(ExtensionStore.newestCommit(in: Data(#"{"message":"API rate limit exceeded"}"#.utf8)) == nil)
        #expect(ExtensionStore.newestCommit(in: Data("not json".utf8)) == nil)

        #expect(ExtensionStore.revisionToRecord(folderCommit: "folder-newest", repositoryCommit: "repo-head") == "folder-newest", "the folder's commit, which is what the check asks GitHub for")
        #expect(ExtensionStore.revisionToRecord(folderCommit: nil, repositoryCommit: "repo-head") == "repo-head", "GitHub could not say: an update is offered once too often, never missed")
    }

    @MainActor @Test func anInstallRecordedTheOldWayIsRecognizedAsUpToDate() throws {
        #expect(ExtensionStore.isAtOrPast(in: Data(#"{"status":"ahead","ahead_by":412}"#.utf8)), "the recorded commit came after the folder's newest change")
        #expect(ExtensionStore.isAtOrPast(in: Data(#"{"status":"identical"}"#.utf8)))
        #expect(!ExtensionStore.isAtOrPast(in: Data(#"{"status":"behind","behind_by":3}"#.utf8)), "the folder changed since: a real update")
        #expect(!ExtensionStore.isAtOrPast(in: Data(#"{"status":"diverged"}"#.utf8)))
        #expect(!ExtensionStore.isAtOrPast(in: Data(#"{"message":"Not Found"}"#.utf8)), "GitHub could not say: the update stays offered")

        let extensions = FileManager.default.temporaryDirectory.appendingPathComponent("floe-store-records-\(UUID().uuidString)")
        let folder = extensions.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extensions) }
        let file = folder.appendingPathComponent(".floe-store.json")
        try Data(#"{"name":"notes","commit":"repo-head","installedAt":700000000}"#.utf8).write(to: file)
        ExtensionStore.record(commit: "folder-newest", for: "notes", in: extensions)
        let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(written["commit"] as? String == "folder-newest")
        #expect(written["installedAt"] as? Double == 700_000_000, "the day it was installed is kept")
        ExtensionStore.record(commit: "x", for: "not-installed", in: extensions)
        #expect(!FileManager.default.fileExists(atPath: extensions.appendingPathComponent("not-installed").path))
    }

    @MainActor @Test func anExtensionThatWasNeverInstalledIsNotInstalledAndHasNoUpdate() async {
        let store = ExtensionStore()
        let name = "floe-tests-\(UUID().uuidString)"
        #expect(!store.isInstalled(name))
        #expect(await !store.hasUpdate(name), "nothing is asked of GitHub about an extension that is not installed")
        #expect(store.cachedDetails(for: name) == nil)
    }

    @MainActor @Test func removingAnExtensionThatIsNotThereChangesNothing() {
        let store = ExtensionStore()
        var reloads = 0
        store.onInstalled = { reloads += 1 }
        store.remove("floe-tests-\(UUID().uuidString)")
        #expect(reloads == 0)
        #expect(store.error == nil)
    }

    @MainActor @Test func aNewStoreHasNothingToShowAndNothingGoing() {
        let store = ExtensionStore()
        #expect(store.catalog.isEmpty)
        #expect(!store.isLoading)
        #expect(store.busy.isEmpty)
        #expect(store.error == nil)
    }

    /// Stands in for GitHub: counts what is asked for and answers a manifest or an icon's bytes.
    private actor Repository {
        private(set) var asked: [URL] = []

        func read(_ url: URL) -> Data {
            asked.append(url)
            return url.lastPathComponent == "package.json" ? Data(#"{"title":"Proton Pass","icon":"icon.png"}"#.utf8) : Data("icon".utf8)
        }
    }

    @MainActor @Test func detailsAreAskedForOnceHoweverManyViewsWantThem() async {
        let repository = Repository()
        let store = ExtensionStore { await repository.read($0) }
        async let row = store.details(for: "proton-pass")
        async let pane = store.details(for: "proton-pass")
        let titles = await [row?.title, pane?.title]
        #expect(titles == ["Proton Pass", "Proton Pass"])
        #expect(await store.details(for: "proton-pass", after: .seconds(60))?.title == "Proton Pass", "what is known is not waited for")
        #expect(await repository.asked.count == 1)
        #expect(store.cachedDetails(for: "proton-pass")?.title == "Proton Pass")
    }

    @MainActor @Test func aRowThatLeavesBeforeItSettlesAsksForNothing() async {
        let repository = Repository()
        let store = ExtensionStore { await repository.read($0) }
        let row = Task { await store.details(for: "proton-pass", after: .seconds(60)) }
        await Task.yield()
        row.cancel()
        #expect(await row.value == nil)
        let asked = await repository.asked
        #expect(asked == [], "typing past a row costs no request")
        #expect(await store.details(for: "proton-pass", after: .zero)?.title == "Proton Pass", "a row that stays is answered")
    }

    @MainActor @Test func anIconIsFetchedOnceAndKeptAsAFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-store-icons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = Repository()
        let store = ExtensionStore(iconFolder: folder) { await repository.read($0) }
        let url = try #require(URL(string: "https://raw.githubusercontent.com/raycast/extensions/main/extensions/proton-pass/assets/my%20icon.png"))
        #expect(store.knownIconFile(for: url) == nil)
        async let first = store.iconFile(for: url)
        async let second = store.iconFile(for: url)
        let files = await [first, second]
        let expected = folder.appendingPathComponent("proton-pass-my icon.png").path
        #expect(files == [expected, expected])
        #expect(try Data(contentsOf: URL(fileURLWithPath: expected)) == Data("icon".utf8))
        #expect(store.knownIconFile(for: url) == expected, "a row that comes back draws it without waiting")
        #expect(await repository.asked.count == 1)
        let again = ExtensionStore(iconFolder: folder) { await repository.read($0) }
        #expect(await again.iconFile(for: url) == expected)
        #expect(await repository.asked.count == 1, "the file is found, not fetched again")
        let installed = URL(fileURLWithPath: "/tmp/floe-installed/assets/icon.png")
        #expect(store.knownIconFile(for: installed) == installed.path, "an installed copy's icon is its own file")
    }

    private func found(_ query: String, in names: [String] = ["1password", "pass", "proton-mail", "proton-pass", "spotify-player"]) -> [String] {
        StoreSearch.results(names.map(StoreListing.init(name:)), query: query).map(\.name)
    }

    @Test(arguments: ["proton pass", "Proton Pass", "protonpass"])
    func aTitleFindsItsExtensionWithSpacesHyphensAndCaseAlike(query: String) {
        #expect(found(query) == ["proton-pass"], "the folder's name answers, with no details fetched")
    }

    @Test func theStoreMatchesAsTheLauncherDoesBestFirst() {
        #expect(found("pass") == ["pass", "proton-pass", "1password"], "a whole name, then a word's start, then letters inside a word")
        #expect(found("proton") == ["proton-mail", "proton-pass"], "equal matches keep the catalog's order")
        #expect(found("spp") == ["spotify-player"], "scattered letters match, as they do in the launcher")
        #expect(found("ppl") == ["spotify-player"])
        #expect(found("zzz").isEmpty)
        #expect(StoreSearch.score("pass", name: "proton-pass") == Fuzzy.score("pass", "proton pass"), "the launcher's own scores")
    }

    @Test(arguments: ["", "   ", "-", " - "])
    func aSearchWithNothingToMatchOnListsEverything(query: String) {
        #expect(found(query) == ["1password", "pass", "proton-mail", "proton-pass", "spotify-player"])
    }
}
