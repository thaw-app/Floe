//
//  Localization.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

extension Bundle {
    /// The bundle that holds `Localizable.xcstrings`. Every `String(localized:)` in Floe passes it.
    static nonisolated let floe: Bundle = {
        #if SWIFT_PACKAGE
            // SwiftPM puts the catalog in the module's bundle, and that bundle follows the main bundle's
            // language, which an unbundled binary and a test runner do not have. So the language is chosen here.
            let module = Bundle.module
            let language = Bundle.preferredLocalizations(from: module.localizations, forPreferences: Locale.preferredLanguages).first
            return language.flatMap { module.url(forResource: $0, withExtension: "lproj") }.flatMap(Bundle.init(url:)) ?? module
        #else
            return .main
        #endif
    }()
}

nonisolated extension LocalizedStringResource.BundleDescription {
    /// Where a `LocalizedStringResource` handed to ThawUI finds Floe's catalog. A resource with no bundle reads the
    /// main bundle, which holds nothing in a `swift build` binary, and nothing warns about it.
    static var floe: Self {
        .atURL(Bundle.floe.bundleURL)
    }
}

nonisolated extension LocalizedStringResource {
    /// Text for ThawUI, read from Floe's catalog. Write `LocalizedStringResource("…", bundle: .floe, comment: "…")`
    /// where a translator needs a comment, since the compiler only takes one from the real initializer.
    static func floe(_ keyAndValue: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(keyAndValue, bundle: .floe)
    }

    /// Text that is not Floe's or is already localized, for a ThawUI view that only takes a resource. The text is an
    /// argument of the key, so it is never looked up or read as a format.
    static func verbatim(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource("\(text)", bundle: .floe)
    }
}

extension LocalizedStringKey {
    /// Text that is not Floe's (an extension's, the user's, or already localized) for a view that only takes a key.
    /// The text is an argument of the key, so it is never looked up, parsed as Markdown or read as a format.
    static func verbatim(_ text: String) -> LocalizedStringKey {
        "\(text)"
    }
}
