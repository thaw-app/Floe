//
//  TypedLocationSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// A web address or a path typed in full leads the results with the row that opens it.
struct TypedLocationSearchProvider: SearchProvider, Sendable {
    /// Read through these, so a test can stand in for the user's home and disk.
    var home: @Sendable () -> String = { FileManager.default.homeDirectoryForCurrentUser.path }
    var kind: @Sendable (String) -> TypedPath.Kind? = { TypedPath.kindOnDisk($0) }

    func contribution(for context: SearchContext) -> SearchContribution {
        guard let item = item(for: context) else { return SearchContribution() }
        return SearchContribution(pinned: [RootResult(item: item, section: nil)])
    }

    private func item(for context: SearchContext) -> RootItem? {
        let text = context.trimmed
        let found: RootItem? = if text.hasPrefix("/") || text.hasPrefix("~") {
            TypedPath.file(for: text, home: home(), kind: kind).map(RootItem.file)
        } else {
            WebAddress(typed: text).map(RootItem.webAddress)
        }
        // A keyword's text and the calculator's answer keep the top. Asked last: it is rarely needed.
        guard let found, QuicklinkSearchProvider.keywordSearchResult(query: text, links: context.quicklinks) == nil,
              !context.scripts.contains(where: { $0.argumentsText(in: context.query) != nil }),
              Calculator.shared.evaluatePreview(context.query) == nil
        else { return nil }
        return found
    }
}

extension LauncherModel {
    /// Opens a typed address in the browser role's app once the panel is gone. Floe itself fetches nothing.
    func open(_ address: WebAddress) {
        hidePanel()
        reset()
        openLink(address.url)
    }
}
