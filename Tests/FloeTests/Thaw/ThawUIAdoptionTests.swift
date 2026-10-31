//
//  ThawUIAdoptionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import SwiftUI
import Testing
import ThawUI

/// What Floe keeps of its own on top of ThawUI's shared pieces.
struct ThawUIAdoptionTests {
    @Test func theReleaseNotesStayWhereTheyWereCachedAndShowEveryRelease() {
        let info = ThawAppInfo.floe
        #expect(info.cacheFolderName == "org.thaw.floe")
        #expect(info.shownMajorVersion == nil)
        #expect(info.showsChannels == false)
        #expect(info.displayName == "Floe")
        #expect(info.changelogURL == AppInfo.changelogURL)
        #expect(info.releasesURL == AppInfo.changelogPageURL)
    }

    @Test func alphaIsNotOfferedAndAStoredOneReadsAsStable() throws {
        #expect(UpdateChannel.floeChannels == [.stable, .beta])
        #expect(UpdateChannel(floeRawValue: "alpha") == nil)
        #expect(UpdateChannel(floeRawValue: "stable") == .stable)
        #expect(UpdateChannel(floeRawValue: "beta") == .beta)
        #expect(UpdateRequest(text: "channel:alpha") == nil)

        let suite = "ThawUIAdoptionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("alpha", forKey: UpdateChannel.defaultsKey)
        #expect(UpdateChannel.stored(in: defaults) == .stable)
        UpdateChannel.beta.store(in: defaults)
        #expect(defaults.string(forKey: "UpdateChannel") == "beta", "the saved value is the one earlier versions wrote")
    }

    @Test func aSavedHotkeyStillDecodesAndOneOutOfRangeDoesNot() throws {
        let saved = Data("[49,3]".utf8)
        #expect(try JSONDecoder().decode(KeyCombination.self, from: saved) == KeyCombination(key: .space, modifiers: [.control, .option]))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination.self, from: Data("[65536,3]".utf8))
        }
    }

    @Test func theSpaceBarAndTheFixedLabelsUseFloesWords() {
        #expect(KeyCode.space.stringValue == "Space")
        #expect(KeyCombination(key: .space, modifiers: .command).displayValue == "⌘ Space")
    }

    @Test func theThemeKeepsFloesGraySelectionAndNeutralHover() {
        #expect(ThawTheme.floe.selection == .flat(fill: .primary.opacity(0.1), edge: .primary.opacity(0.08)))
        #expect(ThawTheme.floe.hoverTint == .primary)
    }

    @Test func theSidebarRowsCarryTheirPagesToTheSharedSidebar() {
        let page = SettingsSidebarPage(page: .about, label: SearchPane.about.label)
        let dimmed = SettingsSidebarPage(page: .extensionPage("zeta"), label: SearchPaneLabel(title: "Zeta", icon: "icon:Terminal", assetsPath: ""), isDimmed: true)
        let rows: [SettingsSidebarRow] = [.heading("Extensions"), .page(dimmed), .page(page)]
        #expect(rows.map(\.sidebarRow) == [.heading("Extensions"), .page(.extensionPage("zeta")), .page(.about)])
        #expect(rows.pagesByID[.extensionPage("zeta")]?.isDimmed == true)
        #expect(rows.pagesByID[.about]?.isDimmed == false)
    }

    @Test func theCreditsPageGoesWhereItAlwaysWent() throws {
        let repository = try #require(URL(string: "https://example.com/floe"))
        let content = AcknowledgementsContent.floe { $0 == "repository" ? repository : nil }
        #expect(content.contributeURL == repository)
        #expect(content.translateURL == nil)
        #expect(content.contributorsURL == AcknowledgementLinks.contributors(repository: repository))
        #expect(content.translatorsURL == AcknowledgementLinks.translators(repository: repository))
        #expect(content.origins.count == Credits.origins.count)
    }

    @Test func theMoreMenuKeepsItsGroupsAndLeavesOutLinksABuildDoesNotHave() throws {
        let everything = try #require(URL(string: "https://example.com"))
        let full = FloeAboutPane.moreMenu { _ in everything }
        #expect(full.map(\.count) == [3, 2, 1])
        let unbundled = FloeAboutPane.moreMenu { _ in nil }
        #expect(unbundled.map(\.count) == [3, 0, 0])
        #expect(full.flatMap(\.self).filter { !$0.title.readsFloesCatalog }.isEmpty)
    }

    /// Text is an extension's as often as Floe's, so it goes through as it is and stays up long enough to read.
    @Test func aMessageStaysUpLongerThanAConfirmation() {
        #expect(ThawHUD.messageDuration > ThawHUD.duration)
    }
}
