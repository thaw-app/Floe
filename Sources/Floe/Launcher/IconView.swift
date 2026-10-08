//
//  IconView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import Synchronization

enum Palette {
    static func color(_ value: Any?) -> Color? {
        guard let string = value as? String else { return nil }
        if string.hasPrefix("#"), let hex = UInt32(string.dropFirst().prefix(6), radix: 16) {
            return Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        switch string.replacingOccurrences(of: "color:", with: "") {
        case "Red": return .red
        case "Orange": return .orange
        case "Yellow": return .yellow
        case "Green": return .green
        case "Blue": return .blue
        case "Purple": return .purple
        case "Magenta": return .pink
        case "PrimaryText": return .primary
        case "SecondaryText": return .secondary
        default: return nil
        }
    }
}

struct IconView: View {
    let value: Any?
    let assetsPath: String
    var size: CGFloat = 18
    /// For an `ImageRenderer`, which draws once: the image is made in that pass instead of in the background.
    var waitsForImage = false

    private enum Resolved {
        case symbol(String), thumbnail(IconSource), remote(URL), text(String), none
    }

    private static let symbols: [String: String] = [
        "Globe": "globe", "Star": "star.fill", "Clipboard": "doc.on.clipboard", "Link": "link", "Trash": "trash",
        "Finder": "folder", "Folder": "folder", "Document": "doc", "Calendar": "calendar", "Clock": "clock",
        "Person": "person", "Gear": "gearshape", "MagnifyingGlass": "magnifyingglass", "Terminal": "terminal",
        "Sidebar": "sidebar.right", "ArrowRight": "arrow.right", "Eye": "eye", "Bubble": "bubble.left",
        "Checkmark": "checkmark", "XMarkCircle": "xmark.circle", "Plus": "plus", "Pencil": "pencil",
        "Download": "arrow.down.circle", "Upload": "arrow.up.circle", "Bookmark": "bookmark", "Heart": "heart",
        "Info": "info.circle", "Warning": "exclamationmark.triangle", "Code": "chevron.left.forwardslash.chevron.right",
        "Window": "macwindow", "AppWindow": "macwindow", "Image": "photo", "Message": "message", "Envelope": "envelope",
        "ArrowClockwise": "arrow.clockwise", "Circle": "circle", "Dot": "circle.fill", "Lock": "lock", "Key": "key",
        "Tag": "tag", "Text": "text.alignleft", "List": "list.bullet", "Play": "play.fill", "Pause": "pause.fill",
    ]

    /// What the system has been asked about a symbol name. The probe makes an NSImage, which a row's
    /// every redraw should not repeat, and whether a name exists never changes while the app runs.
    private static let probedSymbols = Mutex<[String: Bool]>([:])

    private static func isValidSymbol(_ name: String) -> Bool {
        if let known = probedSymbols.withLock({ $0[name] }) {
            return known
        }
        let valid = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        probedSymbols.withLock { $0[name] = valid }
        return valid
    }

    @Environment(\.colorScheme) private var colorScheme

    private func resolve(_ value: Any?) -> Resolved {
        if let dict = value as? [String: Any] {
            if let path = dict["fileIcon"] as? String {
                return .thumbnail(.workspace(path: path))
            }
            // Raycast's { source: { light, dark } } picks per appearance.
            if let source = dict["source"] as? [String: Any] {
                return resolve(colorScheme == .dark ? source["dark"] ?? source["light"] : source["light"] ?? source["dark"])
            }
            return resolve(dict["source"] ?? dict["value"])
        }
        guard let string = value as? String, !string.isEmpty else { return .none }
        if string.hasPrefix("icon:") {
            let name = String(string.dropFirst(5))
            // Raycast names are CamelCase (ArrowUpCircle); most map onto SF Symbols as arrow.up.circle.
            let dotted = name.replacing(#/([a-z0-9])([A-Z])/#) { "\($0.1).\($0.2)" }.lowercased()
            let candidates = [Self.symbols[name], dotted, name.lowercased()].compactMap(\.self)
            let symbol = candidates.first { Self.isValidSymbol($0) }
            return .symbol(symbol ?? "square.dashed")
        }
        if string.hasPrefix("http"), let url = URL(string: string) {
            return .remote(url)
        }
        if string.hasPrefix("data:") {
            return .thumbnail(.data(uri: string))
        }
        // Asset names repeat across extensions (most ship an "icon.png"), so the thumbnail is keyed by the full path.
        if let path = assetPath(string) {
            return .thumbnail(.file(path: path))
        }
        return string.count <= 2 ? .text(string) : .none
    }

    /// An absolute path, or a file in the extension's assets; prefers Raycast's `name@dark.ext` variant in dark mode.
    private func assetPath(_ name: String) -> String? {
        let path = (name as NSString).isAbsolutePath ? name : URL(fileURLWithPath: assetsPath).appendingPathComponent(name).path
        if colorScheme == .dark {
            let url = URL(fileURLWithPath: path)
            let dark = url.deletingPathExtension().path + "@dark." + url.pathExtension
            if FileManager.default.fileExists(atPath: dark) {
                return dark
            }
        }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// tintColor and mask can sit at any level: { value: { source, tintColor } } is common.
    private static func attribute(_ key: String, in value: Any?) -> Any? {
        guard let dict = value as? [String: Any] else { return nil }
        return dict[key] ?? attribute(key, in: dict["value"]) ?? attribute(key, in: dict["source"])
    }

    var body: some View {
        let tint = Palette.color(Self.attribute("tintColor", in: value))
        let isCircle = Self.attribute("mask", in: value) as? String == "circle"
        // Every icon sits in the same glass squircle, Raycast-style: bare
        // symbols next to squircled asset icons read as two different things.
        let squircle = self.squircle(isCircle)
        return Group {
            switch resolve(value) {
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(tint ?? .secondary)
            case let .thumbnail(source):
                IconThumbnailView(source: source, size: size, waitsForImage: waitsForImage) { image in
                    // A tint makes the image a template, as Raycast does for monochrome assets.
                    if let tint {
                        image.resizable().scaledToFit().foregroundStyle(tint)
                    } else {
                        image.resizable().scaledToFill()
                    }
                }
            case let .remote(url):
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            case let .text(text):
                Text(text).font(.system(size: size * 0.55))
            case .none:
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(.quinary, in: squircle)
        .clipShape(squircle)
    }

    private func squircle(_ isCircle: Bool) -> RoundedRectangle {
        isCircle
            ? RoundedRectangle(cornerRadius: size / 2, style: .continuous)
            : RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    }
}
