//
//  Focus.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What a Focus row asks of the Shortcut the user named: macOS has no switch for Focus that an app may flip.
nonisolated struct FocusRequest: Hashable, Sendable {
    enum Change: Hashable, Sendable {
        case toggle, off
        case minutes(Int)
    }

    var change: Change

    static let keyword = "focus"
    static let toggle = FocusRequest(change: .toggle)
    /// Where Return goes while no Shortcut is named: the app the Shortcut is made in.
    static let shortcutsApp = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")

    /// `focus 1 hour` asks for sixty minutes and `focus off` for none. Nil for anything else after the word.
    static func request(in query: String) -> FocusRequest? {
        let words = query.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard words.count == 2, words[0].lowercased() == keyword else { return nil }
        let text = words[1].trimmingCharacters(in: .whitespaces)
        if text.lowercased() == "off" {
            return FocusRequest(change: .off)
        }
        guard let length = TimeLength.leading(text), length.rest.isEmpty, length.seconds > 0, length.seconds <= TimerDraft.longest else { return nil }
        // A Shortcut counts in minutes, so a part of one is a whole one.
        return FocusRequest(change: .minutes(Int((length.seconds / 60).rounded(.up))))
    }

    /// The text the Shortcut receives: the minutes as a number, or the word off or toggle.
    var input: String {
        switch change {
        case .toggle: "toggle"
        case .off: "off"
        case let .minutes(minutes): String(minutes)
        }
    }

    var title: String {
        switch change {
        case .toggle: String(localized: "Toggle Focus", bundle: .floe, comment: "A command that turns a Focus, such as Do Not Disturb, on or off.")
        case .off: String(localized: "Turn Focus Off", bundle: .floe, comment: "The title of the row that turns a Focus, such as Do Not Disturb, off.")
        case let .minutes(minutes): String(localized: "Focus for \(TimeLength.text(TimeInterval(minutes * 60)))", bundle: .floe, comment: "The title of the row that turns a Focus on for a while. The placeholder is how long, such as 1 hr.")
        }
    }

    /// Beside the title: the Shortcut that runs, or that none is named yet.
    static func label(shortcut: String) -> String {
        shortcut.isEmpty ? String(localized: "No Shortcut named in Settings", bundle: .floe, comment: "Beside a Focus row while the user has not said which Shortcut sets their Focus.") : shortcut
    }

    static let keywords = String(localized: "focus, do not disturb, dnd, quiet, silence notifications", bundle: .floe, comment: "Words that find the Toggle Focus command, separated by commas.")
}

/// Toggle Focus is there whatever is typed, and `focus` with a length of time or `off` leads the results.
struct FocusSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        let shortcut = context.focusShortcut.trimmingCharacters(in: .whitespaces)
        var contribution = SearchContribution(ranked: [.focus(.toggle, shortcut: shortcut)])
        if context.text(after: FocusRequest.keyword) != nil, let request = FocusRequest.request(in: context.trimmed) {
            contribution.pinned = [RootResult(item: .focus(request, shortcut: shortcut), section: nil)]
        }
        return contribution
    }
}
