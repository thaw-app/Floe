//
//  PrivacyNetworkTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

struct PrivacyNetworkTests {
    @Test func theAILineNamesWhereAQuestionGoes() {
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "https://openrouter.ai/api/v1") == "Questions go to openrouter.ai, with your key, and nowhere else.")
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "").contains("api.openai.com"), "an empty address is OpenAI's")
        #expect(PrivacyNetwork.aiLine(source: .tools, baseURL: "", tool: "opencode") == "Questions go to the opencode tool, which sends them to the service it is signed in to, on your account there.")
        #expect(PrivacyNetwork.aiLine(source: .tools, baseURL: "") == "The command line tool set on the AI page is not installed, so no question is sent.")
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "https://api.z.ai/api/paas/v4", tool: "claude") == "Questions go to api.z.ai, with your key, and nowhere else.", "a tool is not named when the API answers")
    }

    @Test func whatStaysOnTheMacIsSaidToStayThere() {
        #expect(PrivacyNetwork.aiLine(source: .appleIntelligence, baseURL: "https://api.openai.com/v1").contains("Nothing is sent anywhere"))
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "http://localhost:11434/v1") == "Questions go to the server on this Mac at localhost. Nothing leaves the machine.")
    }

    @Test func anAddressThatIsNotOneClaimsNoDestination() {
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "nonsense") == "Questions go to the address set on the AI page, once it is filled in.")
    }

    @Test func theStoreLineNamesWhatItAsksGitHubFor() {
        let line = PrivacyNetwork.extensionStoreLine
        #expect(line.contains("GitHub"))
        #expect(line.contains("screenshots"), "opening an extension's details asks GitHub for its screenshots")
        #expect(line.contains("npm registry"))
    }

    @Test func aBuildWithoutUpdatesSaysNothingAboutThem() {
        // Under `swift test` the bundle has no feed, so the Updates rows are left out.
        #expect(PrivacyNetwork.updateHost == nil)
    }

    @Test func thePermissionsAreFoundOnThePrivacyPane() {
        #expect(SearchIndex.privacyEntries.allSatisfy { $0.pane == .privacy })
        #expect(SearchIndex.staticEntries.contains { $0.id == "privacy.permissions" })
        #expect(!SearchIndex.generalEntries.contains { $0.section == "Permissions" })
    }

    @Test func everyPrivacyResultOpensTheTabThatHoldsIt() {
        let tabs = Dictionary(uniqueKeysWithValues: SearchIndex.entries(for: .privacy).filter { $0.id != "pane.privacy" }.map { ($0.id, PrivacyTab(entry: $0.id)) })
        #expect(tabs.values.allSatisfy { $0 != nil }, "a result on the page names its tab")
        #expect(tabs["privacy.permissions"] == .access)
        #expect(tabs["privacy.searchSources.files"] == .access)
        #expect(tabs["privacy.contacts"] == .access)
        #expect(tabs["privacy.network"] == .network)
        #expect(tabs["privacy.fetchesExchangeRates"] == .network)
        #expect(tabs["privacy.aiOnThisMacOnly"] == .network)
        #expect(tabs["privacy.remembersSearches"] == .kept)
        #expect(tabs["privacy.keepsReceipts"] == .kept)
        #expect(tabs["privacy.diagnosticLogging"] == .kept)
        #expect(PrivacyTab(entry: "general.launchAtLogin") == nil, "a result elsewhere leaves the tab alone")
    }
}
