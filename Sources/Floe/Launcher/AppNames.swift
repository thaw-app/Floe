//
//  AppNames.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreServices
import Foundation
import Synchronization

/// The names an app answers to besides the one Floe shows. Floe runs in English, so the name it shows is the
/// app's English one, while Spotlight knows the name in the Mac's language and a few more.
nonisolated enum AppNames {
    /// Spotlight's name for the app in the Mac's language, then the other names Spotlight knows it by, such as
    /// Settings for System Settings.
    @Sendable static func spotlight(_ url: URL) -> [String] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return [] }
        let shown = MDItemCopyAttribute(item, kMDItemDisplayName) as? String
        // The SDK has no constant for this attribute, so it goes by name.
        let alternates = MDItemCopyAttribute(item, "kMDItemAlternateNames" as CFString) as? [String] ?? []
        return [shown].compactMap(\.self) + alternates
    }

    /// Each app with its other names and their Latin spellings. Spotlight takes about a millisecond an app, so the
    /// apps are read side by side.
    static func filling(_ apps: [AppEntry], read: @Sendable (URL) -> [String] = spotlight) -> [AppEntry] {
        let found = Mutex([[String]](repeating: [], count: apps.count))
        let urls = apps.map(\.url)
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            let names = read(urls[index])
            found.withLock { $0[index] = names }
        }
        let names = found.withLock(\.self)
        return zip(apps, names).map { app, read in
            var app = app
            app.otherNames = others(of: app.name, among: read)
            app.spellings = ([app.name] + app.otherNames).flatMap(latinSpellings).uniqued().map(\.self)
            return app
        }
    }

    /// The names that differ from the shown one, each once, without a trailing ".app".
    static func others(of shown: String, among names: [String]) -> [String] {
        var seen: Set = [shown.lowercased()]
        return names
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// How a name is typed on a Latin keyboard: without its accents, and for a name in another script, its Latin
    /// spelling with the words apart and together. 备忘录 answers to "bei wang lu", "beiwanglu" and "bwl" that way.
    static func latinSpellings(of name: String) -> [String] {
        guard !name.utf8.allSatisfy({ $0 < 0x80 }) else { return [] }
        let plain = name.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let latin = (name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? plain)
            // The Cyrillic soft sign comes through as a modifier letter, a mark nobody types.
            .filter { ($0.isLetter || $0.isNumber || $0 == " ") && $0.unicodeScalars.first?.properties.generalCategory != .modifierLetter }
        guard latin != plain else { return plain == name ? [] : [plain] }
        let joined = latin.filter { $0 != " " }
        return joined == latin ? [latin] : [latin, joined]
    }
}
