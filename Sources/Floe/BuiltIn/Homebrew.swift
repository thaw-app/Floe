//
//  Homebrew.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A formula or a cask of Homebrew, by the name brew knows it under.
nonisolated struct BrewPackage: Hashable, Sendable {
    var name: String
    var isCask: Bool
    var isInstalled: Bool

    /// Beside the row: what it is, and whether this Mac has it.
    var label: String {
        switch (isCask, isInstalled) {
        case (false, false): String(localized: "Formula", bundle: .floe, comment: "Beside a Homebrew package. A formula is a command line tool Homebrew installs.")
        case (false, true): String(localized: "Formula, installed", bundle: .floe, comment: "Beside a Homebrew package that is on this Mac.")
        case (true, false): String(localized: "Cask", bundle: .floe, comment: "Beside a Homebrew package. A cask is an app Homebrew installs.")
        case (true, true): String(localized: "Cask, installed", bundle: .floe, comment: "Beside a Homebrew package that is on this Mac.")
        }
    }
}

/// "brew ripgrep": Homebrew's packages by name, read from the lists Homebrew keeps on disk. The brew command is never
/// started to search; Return hands the install to the terminal, where it shows what it does and asks what it must.
nonisolated enum Homebrew {
    static let keyword = "brew"
    static let rowLimit = 30

    enum Verb: String {
        case install, upgrade, uninstall
    }

    /// Where Homebrew is and where it keeps its lists of names.
    struct Places: Sendable {
        /// Apple silicon's place, then Intel's.
        var prefixes = [URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")]
        var cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Homebrew/api")

        /// The first prefix that holds the brew command.
        var prefix: URL? {
            prefixes.first { FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("bin/brew").path) }
        }
    }

    /// Every package Homebrew knows and every one installed, installed first. Empty without Homebrew.
    static func read(_ places: Places = Places()) -> [BrewPackage] {
        guard let prefix = places.prefix else { return [] }
        let installedFormulae = Set(folders(in: prefix.appendingPathComponent("Cellar")))
        let installedCasks = Set(folders(in: prefix.appendingPathComponent("Caskroom")))
        let formulae = Set(names(in: places.cache.appendingPathComponent("formula_names.txt"))).union(installedFormulae)
        let casks = Set(names(in: places.cache.appendingPathComponent("cask_names.txt"))).union(installedCasks)
        let all = formulae.map { BrewPackage(name: $0, isCask: false, isInstalled: installedFormulae.contains($0)) }
            + casks.map { BrewPackage(name: $0, isCask: true, isInstalled: installedCasks.contains($0)) }
        return all.filter { isSafe($0.name) }.sorted { ($0.isInstalled ? 0 : 1, $0.name, $0.isCask ? 1 : 0) < ($1.isInstalled ? 0 : 1, $1.name, $1.isCask ? 1 : 0) }
    }

    private static func names(in file: URL) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func folders(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
    }

    /// A name that can go into a command line as it is: a line of a file must not become an option or a second command.
    static func isSafe(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9@+._-]{0,127}/) != nil
    }

    static func command(_ verb: Verb, _ package: BrewPackage) -> String {
        "brew \(verb.rawValue)\(package.isCask ? " --cask" : "") \(package.name)"
    }

    /// What Return does: a package this Mac has is upgraded, any other installed.
    static func primaryVerb(for package: BrewPackage) -> Verb {
        package.isInstalled ? .upgrade : .install
    }

    /// The packages whose name matches, best first. Without a query, the installed ones.
    static func ranked(_ packages: [BrewPackage], query: String) -> [BrewPackage] {
        guard !query.isEmpty else { return packages.filter(\.isInstalled) }
        return packages.ranked { package in Fuzzy.score(query, package.name).map { $0 + (package.isInstalled ? 5 : 0) } }
    }
}

/// The lists are read off the main thread each time, so a package installed a moment ago says so.
struct BrewSearchScope: SearchScope {
    let keyword = Homebrew.keyword
    let title = "Homebrew"
    let emptyTitle = String(localized: "No package matches", bundle: .floe, comment: "Shown when no Homebrew package has the name typed.")
    var read: @Sendable () -> [BrewPackage] = { Homebrew.read() }

    /// The word alone lists what is installed.
    func text(in context: SearchContext) -> String? {
        context.text(afterOrAlone: keyword)
    }

    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        .once { [read] in Homebrew.ranked(read(), query: text).prefix(Homebrew.rowLimit).map(RootItem.brew) }
    }
}
