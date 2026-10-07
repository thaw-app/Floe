//
//  CustomIcon.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// A picture the user chose to stand for an extension, in place of the one it ships with. It is kept
/// as a PNG in the extension's data folder, so it outlasts an update of the extension.
nonisolated enum CustomIcon {
    private static let prefix = "custom-icon-"

    private static func folder(for extensionName: String, in data: URL) -> URL {
        data.appendingPathComponent(extensionName, isDirectory: true)
    }

    /// The chosen picture's path, or nil for an extension that keeps its own.
    static func path(for extensionName: String, in data: URL = Paths.data) -> String? {
        let folder = folder(for: extensionName, in: data)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.max().map { folder.appendingPathComponent($0).path }
    }

    /// Takes a picture in any format AppKit reads. Each one gets a name of its own: icons are
    /// remembered by path, and a second picture under the first one's name would not be drawn.
    static func set(_ source: URL, for extensionName: String, in data: URL = Paths.data, stamp: Int = Int(Date().timeIntervalSince1970 * 1000)) throws {
        guard let image = NSImage(contentsOf: source), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileReadCorruptFile) }
        let folder = folder(for: extensionName, in: data)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        remove(for: extensionName, in: data)
        try png.write(to: folder.appendingPathComponent("\(prefix)\(stamp).png"))
    }

    static func remove(for extensionName: String, in data: URL = Paths.data) {
        let folder = folder(for: extensionName, in: data)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
