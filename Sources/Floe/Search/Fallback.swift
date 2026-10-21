//
//  Fallback.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A row offered under the results of every search, handed what was typed. The user picks them and their order
/// on the Fallbacks page; settings keep them by `id`.
enum Fallback: Hashable {
    /// Run the text as a command line, when it reads as one.
    case shell
    case searchFiles
    case askAI
    case quicklink(UUID)
    /// An extension command, by `ExtensionCommand.id`.
    case command(String)

    private static let quicklinkPrefix = "quicklink:"
    private static let commandPrefix = "command:"

    var id: String {
        switch self {
        case .shell: "shell"
        case .searchFiles: "search-files"
        case .askAI: "ask-ai"
        case let .quicklink(id): Self.quicklinkPrefix + id.uuidString
        case let .command(id): Self.commandPrefix + id
        }
    }

    init?(id: String) {
        switch id {
        case "shell": self = .shell
        case "search-files": self = .searchFiles
        case "ask-ai": self = .askAI
        default:
            if id.hasPrefix(Self.quicklinkPrefix), let uuid = UUID(uuidString: String(id.dropFirst(Self.quicklinkPrefix.count))) {
                self = .quicklink(uuid)
            } else if id.hasPrefix(Self.commandPrefix), id.count > Self.commandPrefix.count {
                self = .command(String(id.dropFirst(Self.commandPrefix.count)))
            } else {
                return nil
            }
        }
    }

    /// The fallbacks in the order chosen. Until the user chooses, they are the ones Floe always had:
    /// the shell guess, the quicklinks marked as fallbacks, Search Files and Ask AI.
    static func order(chosen: [String]?, quicklinks: [Quicklink]) -> [Fallback] {
        guard let chosen else {
            return [.shell] + quicklinks.filter { $0.isFallback && $0.takesQuery }.map { .quicklink($0.id) } + [.searchFiles, .askAI]
        }
        return chosen.compactMap(Fallback.init(id:))
    }

    /// Whether a quicklink can take the typed text: a search, not one page.
    static func accepts(_ link: Quicklink) -> Bool {
        link.takesQuery
    }

    /// Whether a command can take the typed text: its first argument, if it has one, is text, and no other is required.
    static func accepts(_ command: ExtensionCommand) -> Bool {
        guard command.mode != "menu-bar" else { return false }
        guard let first = command.arguments.first else { return true }
        return first.type == "text" && !command.arguments.dropFirst().contains(where: \.required)
    }

    /// The arguments a command is run with as a fallback.
    static func arguments(for command: ExtensionCommand, text: String) -> [String: Any] {
        command.arguments.first.map { [$0.name: text] } ?? [:]
    }
}

/// One fallback as the Fallbacks page lists it: the row it adds, shown with "…" for what will be typed.
struct FallbackChoice: Identifiable {
    let fallback: Fallback
    let row: RootItem
    var id: String {
        fallback.id
    }
}

extension Fallback {
    /// Every fallback that can be chosen here: the built-ins, the quicklinks that search, and the commands that take text.
    static func choices(quicklinks: [Quicklink], commands: [ExtensionCommand]) -> [FallbackChoice] {
        let typed = "\u{2026}"
        let builtIns: [FallbackChoice] = [
            FallbackChoice(fallback: .shell, row: .shell(ShellRow(text: typed, origin: .typed), terminal: nil)),
            FallbackChoice(fallback: .searchFiles, row: .searchFiles(typed)),
            FallbackChoice(fallback: .askAI, row: .askAI(typed)),
        ]
        let links = quicklinks.filter(accepts).map { link in
            FallbackChoice(fallback: .quicklink(link.id), row: .quicklink(link, queryText: typed, fallback: true, keywordSearch: false))
        }
        let commands = commands.filter(accepts).map { command in
            FallbackChoice(fallback: .command(command.id), row: .fallbackCommand(command, text: typed))
        }
        return builtIns + links + commands
    }

    /// The chosen ones that can be offered here, in their order; one this Mac does not have stays chosen, unlisted.
    static func chosen(_ ids: [String]?, among choices: [FallbackChoice], quicklinks: [Quicklink]) -> [FallbackChoice] {
        order(chosen: ids, quicklinks: quicklinks).compactMap { fallback in choices.first { $0.fallback == fallback } }
    }

    /// The list with `id` swapped with the shown row `offset` away. Rows not shown keep their places.
    static func moving(_ id: String, by offset: Int, in ids: [String], shown: [String]) -> [String] {
        guard let index = shown.firstIndex(of: id), shown.indices.contains(index + offset),
              let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: shown[index + offset]) else { return ids }
        var ids = ids
        ids.swapAt(from, to)
        return ids
    }
}
