//
//  SSHSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchContext {
    /// One row per host, each with the terminal it would open in.
    var sshHostRows: [RootItem] {
        let terminal = preferredApps.app(for: .terminal)
        return sshHosts.map { RootItem.sshHost($0, terminal: terminal) }
    }
}

/// The hosts of the SSH configuration. Like System Settings' panes they are only searched for.
struct SSHHostSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        SearchContribution(searchOnly: context.sshHostRows)
    }
}

/// `ssh web`: the hosts that match, and every host for the keyword and a space alone.
struct SSHSearchScope: SearchScope {
    nonisolated static let word = "ssh"

    let keyword = Self.word
    let title = String(localized: "SSH Hosts", bundle: .floe)
    let emptyTitle = String(localized: "No SSH hosts match", bundle: .floe)

    /// Without hosts the word is not a scope, so a search that starts with it stays an ordinary one.
    func text(in context: SearchContext) -> String? {
        guard !context.sshHosts.isEmpty else { return nil }
        return context.text(afterOrWithSpace: keyword)
    }

    func results(for text: String, context: SearchContext) -> [RootItem] {
        context.ranked(context.sshHostRows, for: text)
    }
}
