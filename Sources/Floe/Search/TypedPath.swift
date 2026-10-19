//
//  TypedPath.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A path typed into the search in full: `/Applications`, `~/Downloads`, `~`, or a `file://` address.
nonisolated enum TypedPath {
    enum Kind: Sendable {
        case file, folder
    }

    /// The absolute path the text names, or nil when it is not one. The tilde is expanded, and `.` and
    /// `..` are worked out from the text alone, so nothing here asks the file system.
    static func standardized(_ input: String, home: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let absolute: String
        if text == "~" {
            absolute = home
        } else if text.hasPrefix("~/") {
            absolute = home + text.dropFirst()
        } else if text.hasPrefix("/") {
            absolute = text
        } else if let path = fileAddressPath(text) {
            absolute = path
        } else {
            return nil
        }
        var parts: [Substring] = []
        for part in absolute.split(separator: "/") where part != "." {
            if part == ".." {
                _ = parts.popLast()
            } else {
                parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// The path of `file:///Users/me/My%20File.pdf` as it is on disk. Only this Mac's files: a host other than
    /// localhost names another machine.
    static func fileAddressPath(_ text: String) -> String? {
        guard text.lowercased().hasPrefix("file://"), let url = URL(string: text), url.isFileURL,
              [nil, "", "localhost"].contains(url.host(percentEncoded: false)?.lowercased())
        else { return nil }
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/") ? path : nil
    }

    /// The row for a typed path, as the file search would make it; nil when nothing is there.
    static func file(for input: String, home: String, kind: (String) -> Kind?) -> FileResult? {
        guard let path = standardized(input, home: home), let found = kind(path) else { return nil }
        let url = URL(filePath: path, directoryHint: found == .folder ? .isDirectory : .notDirectory)
        let folder = url.deletingLastPathComponent().path
        return FileResult(
            url: url,
            name: url.lastPathComponent,
            displayPath: folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder,
            contentType: nil,
            lastUsed: nil
        )
    }

    /// One `stat`, which reads the entry's attributes only: nothing is listed and nothing is opened,
    /// so a path inside Downloads or Documents raises no request for access.
    static func kindOnDisk(_ path: String) -> Kind? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return nil }
        return isFolder.boolValue ? .folder : .file
    }
}
