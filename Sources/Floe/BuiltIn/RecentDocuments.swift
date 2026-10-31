//
//  RecentDocuments.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import CoreServices

/// `recent preview`, or Tab on an application: the files used lately that open in that app.
/// An app's own list of recent documents is behind Full Disk Access, so Spotlight says what was used and macOS what opens it.
nonisolated enum RecentDocuments {
    static let keyword = "recent"
    /// How far back a file counts as used lately.
    static let window: TimeInterval = 30 * 24 * 3600
    /// How many of the latest files are asked about, and how many rows are shown.
    static let askedLimit = 400
    static let rowLimit = 30

    struct Used: Equatable, Sendable {
        let url: URL
        let date: Date
    }

    /// The files in the home folder that Spotlight says were used inside the window, latest first. Folders and apps are left out.
    static func recentlyUsed(now: Date = Date()) -> [Used] {
        let text = "kMDItemLastUsedDate >= $time.iso(\(now.addingTimeInterval(-window).ISO8601Format())) && kMDItemContentTypeTree != \"public.folder\" && kMDItemContentType != \"com.apple.application-bundle\""
        guard let query = MDQueryCreate(kCFAllocatorDefault, text as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [kMDQueryScopeHome] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        let found = (0 ..< MDQueryGetResultCount(query)).compactMap { index -> Used? in
            guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            else { return nil }
            return Used(url: URL(fileURLWithPath: path), date: date)
        }
        return found.sorted { $0.date > $1.date }
    }

    /// The ones `app` opens when they are double-clicked, in the order given.
    static func documents(of app: URL, among files: [Used], opener: (URL) -> URL?) -> [Used] {
        let wanted = app.standardizedFileURL.path
        var kept: [Used] = []
        for file in files.prefix(askedLimit) where opener(file.url)?.standardizedFileURL.path == wanted {
            kept.append(file)
            if kept.count == rowLimit {
                break
            }
        }
        return kept
    }

    /// The app a name stands for: the one called that, or else the first whose name starts with it.
    static func app(named name: String, in apps: [AppEntry]) -> AppEntry? {
        let wanted = name.lowercased()
        return apps.first { $0.name.lowercased() == wanted } ?? apps.first { $0.name.lowercased().hasPrefix(wanted) }
    }
}

struct RecentDocumentsScope: SearchScope {
    let keyword = RecentDocuments.keyword
    let title = String(localized: "Recently Used Files", bundle: .floe)
    let emptyTitle = String(localized: "No recently used file opens in that app", bundle: .floe)
    var recentlyUsed: @Sendable () -> [RecentDocuments.Used] = { RecentDocuments.recentlyUsed() }
    var opener: @Sendable (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) }

    func results(for _: String, context _: SearchContext) -> [RootItem] {
        []
    }

    /// Spotlight is asked off the main thread; nothing is asked when the text names no app.
    func updates(for text: String, context: SearchContext) -> AsyncStream<[RootItem]>? {
        guard let app = RecentDocuments.app(named: text, in: context.apps) else { return nil }
        return .once { [recentlyUsed, opener] in
            RecentDocuments.documents(of: app.url, among: recentlyUsed(), opener: opener).map { used in
                .file(FileResult(url: used.url, name: used.url.lastPathComponent, displayPath: FileResult.displayPath(of: used.url.path, home: NSHomeDirectory()), contentType: nil, lastUsed: used.date))
            }
        }
    }
}
