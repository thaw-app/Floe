//
//  FloeAboutPane.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// The shared About page with Floe's build, links and menu. What's New and Credits open in `ReadingWindow`, since
/// Floe's settings are a process of their own without Thaw's window scenes, and the updates card shows only in a
/// build that can update.
struct FloeAboutPane: View {
    let updatesManager: UpdatesManager

    var body: some View {
        AboutSettingsPane(
            appName: AppInfo.displayName,
            version: AboutVersionDetails(
                version: AppInfo.versionString,
                build: AppInfo.buildString,
                commit: AppInfo.commitString,
                report: AppInfo.buildDescription
            ),
            links: AboutLinks(
                sourceCode: AppInfo.repositoryURL,
                reportBug: AppInfo.issuesURL,
                support: AppInfo.link("sponsor")
            ),
            moreMenu: Self.moreMenu(link: AppInfo.link),
            updates: updatesManager.isAvailable
                ? AboutUpdateControls(model: updatesManager, channels: UpdateChannel.floeChannels, strings: .floe)
                : nil,
            copyright: Text(AppInfo.copyrightString),
            strings: .floe,
            showWhatsNew: { ReadingWindow.releaseNotes.show() },
            showCredits: { ReadingWindow.acknowledgements.show() }
        )
    }

    /// The secondary destinations behind the actions button: Floe's folders, the community, then Thaw. A web link
    /// a build does not have, as under `swift run`, leaves its entry out.
    static func moreMenu(link: (String) -> URL?) -> [[AboutMenuItem]] {
        let community = [
            link("discord").map { AboutMenuItem(.floe("Join the Discord"), systemImage: "bubble.left.and.bubble.right", url: $0) },
            link("raycastExtensions").map { AboutMenuItem(.floe("Raycast Extension Store"), systemImage: "storefront", url: $0) },
        ]
        return [
            [
                AboutMenuItem(.floe("Extensions Folder"), systemImage: "puzzlepiece.extension") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.extensions])
                },
                AboutMenuItem(.floe("Data Folder"), systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.data])
                },
                AboutMenuItem(.floe("Raycast Extensions Folder"), systemImage: "folder.badge.gearshape") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.raycastExtensions])
                },
            ],
            community.compactMap(\.self),
            [link("thaw").map { AboutMenuItem(.verbatim("Thaw"), systemImage: "snowflake", url: $0) }].compactMap(\.self),
        ]
    }
}

extension UpdatesManager: AboutUpdatesModel {}
