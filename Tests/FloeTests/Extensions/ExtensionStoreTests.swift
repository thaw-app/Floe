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
}
