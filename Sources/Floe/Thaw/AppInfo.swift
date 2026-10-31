//
//  AppInfo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Thaw 3's Constants, as far as the About page and the release notes read them.

import Foundation

/// What the About page shows, read from the bundle so a build stamps its own version and commit.
nonisolated enum AppInfo {
    static let displayName = "Floe"
    static let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    static let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let commitString = Bundle.main.object(forInfoDictionaryKey: "GitCommitSHA") as? String ?? "unknown"
    static let copyrightString = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    private static let links = Bundle.main.object(forInfoDictionaryKey: "FloeLinks") as? [String: String] ?? [:]

    /// A web link from Info.plist's FloeLinks; nil when run outside the app bundle (swift run).
    static func link(_ name: String) -> URL? {
        links[name].flatMap(URL.init(string:))
    }

    static var repositoryURL: URL? {
        link("repository")
    }

    /// The changelog as text, for the release notes reader, and as a page, for the browser.
    static let changelogURL = URL(string: "https://raw.githubusercontent.com/thaw-app/Floe/main/CHANGELOG.md")!
    static let changelogPageURL = URL(string: "https://github.com/thaw-app/Floe/blob/main/CHANGELOG.md")!

    static var issuesURL: URL? {
        repositoryURL?.appendingPathComponent("issues")
    }

    static var buildDescription: String {
        """
        \(displayName) \(versionString) (\(buildString))
        Commit: \(commitString)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }
}
