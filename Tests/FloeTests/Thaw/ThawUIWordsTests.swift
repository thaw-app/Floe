//
//  ThawUIWordsTests.swift
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

/// Floe's words and data on ThawUI's shared views, drawn off screen.
@MainActor
struct ThawUIWordsTests {
    private func size(of view: some View) -> NSSize {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private func manager() -> (UpdatesManager, ScratchDefaults) {
        let scratch = ScratchDefaults()
        let configuration = UpdateConfiguration(feedURL: nil, publicKey: nil)
        return (UpdatesManager(configuration: configuration, defaults: scratch.defaults), scratch)
    }

    @Test func theBuildReportNamesTheAppItsVersionAndItsCommit() {
        let report = AppInfo.buildDescription
        #expect(report.contains("Floe \(AppInfo.versionString) (\(AppInfo.buildString))"))
        #expect(report.contains("Commit: \(AppInfo.commitString)"))
        #expect(report.contains("macOS "))
    }

    @Test func aLinkTheBuildDoesNotHaveIsNil() {
        #expect(AppInfo.link("no such link") == nil)
        #expect((AppInfo.issuesURL == nil) == (AppInfo.repositoryURL == nil))
        #expect(AppInfo.copyrightString == Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
    }

    @Test func theAboutPageDrawsWithoutAnUpdatesCardInABuildThatCannotUpdate() {
        let (updates, scratch) = manager()
        #expect(!updates.isAvailable)
        #expect(size(of: FloeAboutPane(updatesManager: updates)).width > 0)
        withExtendedLifetime(scratch) {}
    }

    @Test func theUpdateSwitchDrawsNothingInABuildThatCannotUpdate() {
        let (updates, scratch) = manager()
        #expect(size(of: AutomaticUpdateCheckToggle(updatesManager: updates)) == .zero)
        withExtendedLifetime(scratch) {}
    }

    @Test func theConsentSheetLeavesTheViewItIsOnDrawn() {
        let (updates, scratch) = manager()
        #expect(size(of: Text(verbatim: "Page").updateConsentSheet(updates)).width > 0)
        withExtendedLifetime(scratch) {}
    }

    @Test func everyBeamHasItsOwnName() {
        let titles = [SearchFieldBeam.off, .colorful, .mono, .ocean, .sunset].map(\.title)
        #expect(titles == ["Off", "Colorful", "Mono", "Ocean", "Sunset"])
    }

    @Test func theSharedControlsDrawWithFloesWords() {
        #expect(size(of: Toggle("On", isOn: .constant(true)).toggleStyle(.thawCheckbox)).width > 0)
        #expect(size(of: ThawFirstRunHint(systemImage: "star", "Hint") {
            // Never dismissed here.
        }).width > 0)
        #expect(size(of: SettingsFilterField(prompt: "Find", text: .constant("x"))).width > 0)
        #expect(size(of: NoMatchesState(query: "x")).width > 0)
        #expect(size(of: HotkeyRecorder(keyCombination: .constant(nil)) { Text(verbatim: "Key") }).width > 0)
    }

    @Test func aPermissionDrawsWithFloesWords() throws {
        let permission = try #require(DataPermissions.system.first)
        #expect(size(of: permission.titleText).width > 0)
        #expect(size(of: PermissionLabel(permission: permission)).width > 0)
        #expect(size(of: PermissionStatusControl(permission: permission)).width > 0)
    }

    @Test func aDataPermissionNamesWhetherSettingsCanTakeOverAfterADecline() {
        #expect(DataPermissions.system.map(\.hasSettingsPane) == [true, true, true])
    }

    @Test func releaseFactsAndAMissingReleaseAreWorded() {
        _ = WhatsNewStrings.floe.releaseSubtitle(Text(verbatim: "Today"), "3 changes")
        _ = WhatsNewStrings.floe.noRelease(Text(verbatim: "beta"), "Floe")
        #expect(WhatsNewStrings.floe.releaseTitle("Unreleased") != WhatsNewStrings.floe.releaseTitle("1.0"))
    }
}
