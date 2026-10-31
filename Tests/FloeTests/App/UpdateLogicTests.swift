//
//  UpdateLogicTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing
import ThawUI

/// 32 zero bytes in base64: the right shape for an EdDSA public key, and not a real one.
private let wellFormedKey = Data(count: 32).base64EncodedString()
private let feed = "https://thaw-app.github.io/Floe/appcast.xml"

struct UpdateConfigurationTests {
    @Test func aFeedAndAKeyTurnUpdatesOn() {
        let configuration = UpdateConfiguration(feedURL: feed, publicKey: wellFormedKey)
        #expect(configuration.hasUsableFeed)
        #expect(configuration.hasUsableKey)
        #expect(configuration.isConfigured)
    }

    @Test(arguments: ["", "   ", "PLACEHOLDER", "not base64!", Data(count: 16).base64EncodedString(), Data(count: 64).base64EncodedString()])
    func anEmptyOrMalformedKeyKeepsUpdatesOff(key: String) {
        let configuration = UpdateConfiguration(feedURL: feed, publicKey: key)
        #expect(configuration.hasUsableFeed)
        #expect(configuration.hasUsableKey == false)
        #expect(configuration.isConfigured == false)
    }

    @Test(arguments: ["", "http://thaw-app.github.io/Floe/appcast.xml", "file:///tmp/appcast.xml", "appcast.xml", "https://"])
    func aFeedThatIsNotHTTPSKeepsUpdatesOff(feedURL: String) {
        let configuration = UpdateConfiguration(feedURL: feedURL, publicKey: wellFormedKey)
        #expect(configuration.hasUsableFeed == false)
        #expect(configuration.isConfigured == false)
    }

    @Test func missingValuesKeepUpdatesOff() {
        #expect(UpdateConfiguration(feedURL: nil, publicKey: nil).isConfigured == false)
        #expect(UpdateConfiguration(info: nil).isConfigured == false, "swift run has no Info.plist")
        #expect(UpdateConfiguration(info: [:]).isConfigured == false)
        #expect(UpdateConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": 7]).isConfigured == false)
    }

    @Test func readsBothKeysFromAnInfoDictionary() {
        let configuration = UpdateConfiguration(info: ["SUFeedURL": " \(feed)\n", "SUPublicEDKey": " \(wellFormedKey) "])
        #expect(configuration == UpdateConfiguration(feedURL: feed, publicKey: wellFormedKey))
        #expect(configuration.feedURL == feed, "surrounding whitespace is dropped")
        #expect(configuration.isConfigured)
    }

    @Test func onlyADebugBuildFollowsTheRehearsalFeed() {
        let configuration = UpdateConfiguration(feedURL: feed, publicKey: wellFormedKey)
        let local = "http://localhost:8000/appcast.xml"
        #expect(configuration.feedURLString(isDebugBuild: true, debugFeed: local) == local)
        #expect(configuration.feedURLString(isDebugBuild: true, debugFeed: nil) == feed)
        #expect(configuration.feedURLString(isDebugBuild: true, debugFeed: "") == feed)
        #expect(configuration.feedURLString(isDebugBuild: false, debugFeed: local) == feed)
    }

    @Test func aDebugBuildChecksOnlyAgainstARehearsalFeed() {
        #expect(UpdateConfiguration.allowsManualCheck(isDebugBuild: false, debugFeed: nil))
        #expect(UpdateConfiguration.allowsManualCheck(isDebugBuild: true, debugFeed: nil) == false)
        #expect(UpdateConfiguration.allowsManualCheck(isDebugBuild: true, debugFeed: "") == false)
        #expect(UpdateConfiguration.allowsManualCheck(isDebugBuild: true, debugFeed: "http://localhost:8000/appcast.xml"))
    }
}

struct UpdateConsentTests {
    private let scratch: ScratchDefaults

    init() throws {
        scratch = ScratchDefaults()
    }

    @Test func asksOnceAndOnlyWhenUpdatesAreConfigured() {
        let consent = UpdateConsent(defaults: scratch.defaults)
        #expect(consent.hasAnswered == false)
        #expect(consent.shouldAsk(isConfigured: true))
        #expect(consent.shouldAsk(isConfigured: false) == false)

        consent.hasAnswered = true
        #expect(consent.shouldAsk(isConfigured: true) == false)
    }

    @Test func theUpdaterStartsAtLaunchOnlyAfterAnAnswer() {
        let consent = UpdateConsent(defaults: scratch.defaults)
        #expect(consent.shouldStartUpdater(isConfigured: true) == false)

        consent.hasAnswered = true
        #expect(consent.shouldStartUpdater(isConfigured: true))
        #expect(consent.shouldStartUpdater(isConfigured: false) == false)
    }

    @Test func theAnswerIsStoredInTheGivenDefaults() {
        UpdateConsent(defaults: scratch.defaults).hasAnswered = true
        #expect(scratch.defaults.bool(forKey: "hasSeenUpdateConsent"))
        #expect(UpdateConsent(defaults: scratch.defaults).hasAnswered)
    }
}

struct AutomaticUpdatesTests {
    @Test func sparklesTwoSwitchesMapToOneChoice() {
        #expect(AutomaticUpdates(checks: false, downloads: false) == .off)
        #expect(AutomaticUpdates(checks: false, downloads: true) == .off, "downloading needs checking")
        #expect(AutomaticUpdates(checks: true, downloads: false) == .check)
        #expect(AutomaticUpdates(checks: true, downloads: true) == .download)
    }

    @Test(arguments: AutomaticUpdates.allCases)
    func aChoiceRoundTripsThroughTheSwitches(choice: AutomaticUpdates) {
        #expect(AutomaticUpdates(checks: choice.checks, downloads: choice.downloads) == choice)
    }

    @Test func titles() {
        #expect(AutomaticUpdates.allCases.map(\.title) == ["Off", "Check only", "Check and download"])
        #expect(AutomaticUpdates.allCases.map(\.shortTitle) == ["Off", "Check", "Download"], "short enough for a pill")
    }
}

struct UpdateChannelTests {
    private let scratch: ScratchDefaults

    init() throws {
        scratch = ScratchDefaults()
    }

    @Test func stableIsTheDefault() {
        #expect(UpdateChannel.stored(in: scratch.defaults) == .stable)
    }

    @Test func anUnknownStoredValueFallsBackToStable() {
        scratch.defaults.set("alpha", forKey: UpdateChannel.defaultsKey)
        #expect(UpdateChannel.stored(in: scratch.defaults) == .stable)
    }

    @Test(arguments: UpdateChannel.floeChannels)
    func aChosenChannelComesBack(channel: UpdateChannel) {
        channel.store(in: scratch.defaults)
        #expect(UpdateChannel.stored(in: scratch.defaults) == channel)
        #expect(channel.id == channel.rawValue)
    }

    @Test func betaAddsItsSparkleChannelAndStableAddsNone() {
        #expect(UpdateChannel.stable.allowedSparkleChannels.isEmpty)
        #expect(UpdateChannel.beta.allowedSparkleChannels == ["beta"])
        #expect(UpdateChannel.floeChannels.map(\.title) == ["Stable", "Beta"])
    }
}

struct UpdateTextTests {
    @Test func theMenuItemNamesAPendingUpdate() {
        #expect(UpdateText.menuTitle(pendingVersion: nil) == "Check for Updates…")
        #expect(UpdateText.menuTitle(pendingVersion: "") == "Check for Updates…")
        #expect(UpdateText.menuTitle(pendingVersion: "0.2.0") == "Update to 0.2.0…")
    }

    @Test func lastCheckedSaysWhenOrThatItHasNotHappened() {
        #expect(String(localized: AboutUpdateStrings.floe.notChecked) == "Not checked yet")
        #expect(String(localized: AboutUpdateStrings.floe.lastChecked("then")) == "Last checked then")
    }

    @Test func aCheckCanBeginBeforeTheUpdaterStartsOrWhenSparkleAllowsIt() {
        #expect(UpdateText.canCheckNow(updaterStarted: false, updaterCanCheck: false))
        #expect(UpdateText.canCheckNow(updaterStarted: true, updaterCanCheck: true))
        #expect(UpdateText.canCheckNow(updaterStarted: true, updaterCanCheck: false) == false)
    }
}
