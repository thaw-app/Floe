//
//  SSHHosts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Foundation

/// A host named in the SSH configuration: what the user would type after "ssh".
nonisolated struct SSHHost: Hashable, Identifiable, Sendable {
    let alias: String
    var hostName: String?
    var user: String?

    /// Made from the alias alone, so a favorite and the usage record outlive a change of address.
    var id: String {
        "ssh-host:\(alias)"
    }

    /// Where the alias leads, as far as the configuration says: "user@hostname", or the part there is.
    var subtitle: String? {
        switch (user, hostName) {
        case let (user?, hostName?): "\(user)@\(hostName)"
        case let (user?, nil): user
        case let (nil, hostName?): hostName
        case (nil, nil): nil
        }
    }

    /// The other words the host is found by.
    var keywords: [String] {
        [hostName, user].compactMap(\.self)
    }

    /// What Copy Host Name copies: the address when the configuration gives one.
    var copyableName: String {
        hostName ?? alias
    }
}

/// How the configuration's files are read. Tests pass their own, so none reads the user's.
nonisolated struct SSHConfigFiles: Sendable {
    /// The home folder: what "~" stands for, and where ".ssh" is.
    var home: String
    /// A file's text; nil when it is missing or cannot be read.
    var read: @Sendable (String) -> String?
    /// The names in a folder, for an Include with a wildcard.
    var list: @Sendable (String) -> [String]

    static let user = SSHConfigFiles(
        home: NSHomeDirectory(),
        read: { try? String(contentsOfFile: $0, encoding: .utf8) },
        list: { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
    )
}

/// Reads the host names out of an SSH configuration. Nothing else in it is kept: no keys, no ports, no options.
nonisolated enum SSHConfig {
    /// How deep an Include may nest, as in ssh itself.
    static let maxDepth = 16

    /// A "Host" line with what follows it. The lines before the first one apply to every host.
    struct Block: Equatable, Sendable {
        var patterns: [String]
        var hostName: String?
        var user: String?
    }

    /// The hosts of the user's configuration, in the order it names them. Empty when there is none.
    static func hosts(files: SSHConfigFiles) -> [SSHHost] {
        hosts(in: blocks(at: files.home + "/.ssh/config", files: files, stack: [], opening: ["*"]))
    }

    /// Each plain name once, with the first address and user among the blocks that apply to it, as ssh reads them.
    static func hosts(in blocks: [Block]) -> [SSHHost] {
        blocks.flatMap(\.patterns).filter(isName).uniqued().map { alias in
            let applying = blocks.filter { applies($0.patterns, to: alias) }
            return SSHHost(
                alias: alias,
                hostName: applying.firstNonNil(\.hostName)?.replacingOccurrences(of: "%h", with: alias),
                user: applying.firstNonNil(\.user)
            )
        }
    }

    /// A pattern that is one host's name: no wildcard and no negation.
    static func isName(_ pattern: String) -> Bool {
        !pattern.isEmpty && !pattern.hasPrefix("!") && !pattern.contains("*") && !pattern.contains("?")
    }

    /// Whether a block's patterns cover a host: one of them matches, and no negated one does.
    static func applies(_ patterns: [String], to alias: String) -> Bool {
        let isExcluded = patterns.contains { $0.hasPrefix("!") && matches(String($0.dropFirst()), alias) }
        return !isExcluded && patterns.contains { !$0.hasPrefix("!") && matches($0, alias) }
    }

    /// A match with "*" for any run of characters and "?" for one.
    static func matches(_ pattern: String, _ text: String) -> Bool {
        let pattern = Array(pattern)
        let text = Array(text)
        var patternIndex = 0
        var textIndex = 0
        // Where the last "*" was, and how much of the text it has taken so far.
        var star: Int?
        var mark = 0
        while textIndex < text.count {
            if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                star = patternIndex
                mark = textIndex
                patternIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == "?" || pattern[patternIndex] == text[textIndex] {
                patternIndex += 1
                textIndex += 1
            } else if let star {
                patternIndex = star + 1
                mark += 1
                textIndex = mark
            } else {
                return false
            }
        }
        return pattern[patternIndex...].allSatisfy { $0 == "*" }
    }

    /// One file's blocks with those of the files it includes, in the order ssh reads them. `opening`
    /// is who the first lines apply to; `stack` is the files being read, which stops a cycle.
    private static func blocks(at path: String, files: SSHConfigFiles, stack: [String], opening: [String]) -> [Block] {
        guard stack.count < maxDepth, !stack.contains(path), let text = files.read(path) else { return [] }
        var blocks = [Block(patterns: opening)]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let (keyword, values) = directive(String(line)) else { continue }
            let last = blocks.count - 1
            switch keyword {
            case "host":
                blocks.append(Block(patterns: values))
            case "match":
                // A Match block names no host, and what it sets depends on things only ssh knows.
                blocks.append(Block(patterns: []))
            case "hostname":
                blocks[last].hostName = blocks[last].hostName ?? values.first
            case "user":
                blocks[last].user = blocks[last].user ?? values.first
            case "include":
                let patterns = blocks[last].patterns
                blocks += values.flatMap { paths(matching: $0, files: files) }
                    .flatMap { self.blocks(at: $0, files: files, stack: stack + [path], opening: patterns) }
                // The block that included them goes on after them.
                blocks.append(Block(patterns: patterns))
            default:
                break
            }
        }
        return blocks
    }

    /// A line as its keyword in lower case and its values; nil for an empty line or a comment.
    static func directive(_ line: String) -> (keyword: String, values: [String])? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        guard let end = line.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "=" }) else {
            return (line.lowercased(), [])
        }
        var rest = line[end...].drop { $0 == " " || $0 == "\t" }
        if rest.first == "=" {
            rest = rest.dropFirst()
        }
        return (line[..<end].lowercased(), values(in: String(rest)))
    }

    /// Values split at spaces, with a quoted one kept whole. A "#" where a value would start ends the line.
    static func values(in text: String) -> [String] {
        var values: [String] = []
        var current = ""
        var isQuoted = false
        var hasValue = false
        for character in text {
            if character == "\"" {
                isQuoted.toggle()
                hasValue = true
            } else if !isQuoted, character == " " || character == "\t" {
                if hasValue {
                    values.append(current)
                }
                current = ""
                hasValue = false
            } else if !isQuoted, !hasValue, character == "#" {
                break
            } else {
                current.append(character)
                hasValue = true
            }
        }
        return hasValue ? values + [current] : values
    }

    /// The files an Include names: "~" is the home folder, a relative path starts in ".ssh", and a
    /// name with "*" or "?" stands for every name in its folder that matches, in order.
    static func paths(matching pattern: String, files: SSHConfigFiles) -> [String] {
        var path = pattern
        if path == "~" || path.hasPrefix("~/") {
            path = files.home + path.dropFirst()
        } else if !path.hasPrefix("/") {
            path = files.home + "/.ssh/" + path
        }
        let found = path.split(separator: "/").map(String.init).reduce([""]) { folders, name in
            guard name.contains("*") || name.contains("?") else { return folders.map { $0 + "/" + name } }
            return folders.flatMap { paths(in: $0, named: name, files: files) }
        }
        // One spelling per file, so a file that includes itself by another path is still seen as a cycle.
        return found.map { URL(fileURLWithPath: $0, isDirectory: false).standardized.path }
    }

    /// The paths in a folder whose name matches one with "*" or "?", in order.
    private static func paths(in folder: String, named name: String, files: SSHConfigFiles) -> [String] {
        files.list(folder.isEmpty ? "/" : folder)
            // As in a shell, a wildcard does not find hidden files.
            .filter { matches(name, $0) && (!$0.hasPrefix(".") || name.hasPrefix(".")) }
            .sorted()
            .map { folder + "/" + $0 }
    }
}
