//
//  ThawUIWords.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

// ThawUI holds no text of its own. These give it Floe's words, each naming Floe's bundle: a bare literal compiles and
// reads the main bundle instead. ThawUIStringsGuardTests holds every call to ThawUI to that.

extension ToggleStyle where Self == ThawCheckboxToggleStyle {
    /// The shared checkbox, with Floe's names for its state.
    static var thawCheckbox: ThawCheckboxToggleStyle {
        .thawCheckbox(onValue: UpdateConsentStrings.floe.checkboxOn, offValue: UpdateConsentStrings.floe.checkboxOff)
    }
}

private nonisolated let dismissHint = LocalizedStringResource("Dismiss hint", bundle: .floe, comment: "Spoken for the button that closes a first-run hint.")

extension ThawFirstRunHint {
    init(
        systemImage: String,
        _ text: LocalizedStringResource,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.init(systemImage: systemImage, text, dismissLabel: dismissHint, actionTitle: actionTitle, action: action, onDismiss: onDismiss)
    }
}

extension ThawHintTipViewStyle {
    init() {
        self.init(dismissLabel: dismissHint)
    }
}

extension ListRowIcon.Source {
    /// An extension's or an app's icon, as `IconView` reads it.
    static func icon(_ value: Any?, assetsPath: String) -> ListRowIcon.Source {
        .custom(AnyView(IconView(value: value, assetsPath: assetsPath, size: ListStyle.imageSize)))
    }
}

// MARK: - Search field

nonisolated extension SearchFieldBeam {
    var title: String {
        switch self {
        case .off: String(localized: "Off", bundle: .floe, comment: "No beam around the search field.")
        case .colorful: String(localized: "Colorful", bundle: .floe, comment: "A beam around the search field in every colour.")
        case .mono: String(localized: "Mono", bundle: .floe, comment: "A beam around the search field in greys alone.")
        case .ocean: String(localized: "Ocean", bundle: .floe, comment: "A beam around the search field in blues and violets.")
        case .sunset: String(localized: "Sunset", bundle: .floe, comment: "A beam around the search field in oranges, pinks and reds.")
        }
    }
}

nonisolated extension SearchFieldShape {
    var title: String {
        switch self {
        case .rounded: String(localized: "Rounded", bundle: .floe, comment: "A shape for the search field.")
        case .capsule: String(localized: "Capsule", bundle: .floe, comment: "A shape for the search field.")
        case .square: String(localized: "Square", bundle: .floe, comment: "A shape for the search field.")
        }
    }
}

// MARK: - HUD

extension ThawHUD {
    /// How long a message stays up. Thaw's are two words; an extension's are sentences.
    static let messageDuration: Duration = .milliseconds(1600)

    /// Shows a message Floe has already localized, or an extension's own text.
    static func show(symbol: String? = nil, text: String, on screen: NSScreen? = nil, placement: ThawHUDPlacement = .center) {
        show(symbol: symbol, text: .verbatim(text), on: screen, placement: placement, displayDuration: messageDuration)
    }
}

// MARK: - Filter field

extension SettingsFilterField {
    /// A page's own search, with Floe's name for its clear button.
    init(prompt: LocalizedStringResource, text: Binding<String>) {
        self.init(prompt: prompt, clearLabel: .floe("Clear"), text: text)
    }
}

extension NoMatchesState {
    /// What a page's filter shows when nothing matches.
    init(query: String) {
        self.init(
            query: query,
            title: { .floe("No results for “\($0)”") },
            caption: .floe("Check the spelling or try a shorter term.")
        )
    }
}
