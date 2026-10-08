//
//  Selection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices
import CoreGraphics

/// Errors with the message the extension sees.
enum SelectionError: LocalizedError {
    case accessibilityOff
    case noSelectedText
    case finderNotFrontmost
    case finderEmpty
    case finderAutomation(String)
    /// macOS refused the script (error -1743): Floe may not control Finder.
    case automationRefused

    var errorDescription: String? {
        switch self {
        case .accessibilityOff:
            String(localized: "Getting the selected text needs Accessibility access. Turn it on under System Settings › Privacy & Security › Accessibility.", bundle: .floe)
        case .noSelectedText:
            // The sentence Raycast's API fails with, which an extension may look for. It stays as written.
            "Unable to get selected text from frontmost application"
        case .finderNotFrontmost:
            String(localized: "The Finder isn't frontmost, so there is no Finder selection to read.", bundle: .floe)
        case .finderEmpty:
            String(localized: "No files are selected in the Finder.", bundle: .floe)
        case let .finderAutomation(details):
            details
        case .automationRefused:
            String(localized: "Floe needs Automation access to read the Finder selection. Turn it on under System Settings › Privacy & Security › Automation, then try again. (-1743)", bundle: .floe)
        }
    }
}

/// The selected text of the frontmost app: what Accessibility reports, else a borrowed Command-C.
nonisolated enum SelectedText {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @concurrent
    static func current() async throws -> String {
        guard isTrusted else { throw SelectionError.accessibilityOff }
        if let text = accessibilitySelectedText(), !text.isEmpty {
            return text
        }
        return try await copiedSelectedText()
    }

    /// Whatever the focused element reports as selected.
    static func accessibilitySelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var app: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &app) == .success,
              let app, CFGetTypeID(app) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        let appElement = app as! AXUIElement
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedText" as CFString, &selected) == .success else { return nil }
        if let text = selected as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    /// Borrows the pasteboard with Command-C, then restores it only when nothing else changed it.
    @concurrent
    static func copiedSelectedText() async throws -> String {
        let pasteboard = NSPasteboard.general
        let saved = SavedPasteboard.capture(pasteboard)
        let before = pasteboard.changeCount
        simulateCommandC()
        var copied: String?
        for _ in 0 ..< 10 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != before {
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        let afterCopy = pasteboard.changeCount
        let text = (copied ?? pasteboard.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Only restore when the pasteboard still holds what Command-C put there.
        if pasteboard.changeCount == afterCopy {
            saved.restore(to: pasteboard)
        }
        guard !text.isEmpty else { throw SelectionError.noSelectedText }
        return text
    }

    static func simulateCommandC() {
        KeySimulation.command(keyCode: 8)
    }
}

/// The Finder's selection, as POSIX paths.
enum FinderSelection {
    private static nonisolated let selectionScript = """
    tell application "Finder"
      set sel to selection
      set out to ""
      repeat with itemRef in sel
        set out to out & POSIX path of (itemRef as alias) & "\\n"
      end repeat
      return out
    end tell
    """

    /// Where a new folder would land: the front window's folder, or the desktop without a window.
    private static nonisolated let folderScript = #"tell application "Finder" to return POSIX path of (insertion location as alias)"#

    static func current() throws -> [[String: String]] {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            throw SelectionError.finderNotFrontmost
        }
        let paths = try paths(from: selectionScript)
        guard !paths.isEmpty else { throw SelectionError.finderEmpty }
        return paths.map { ["path": $0] }
    }

    /// What is selected, or the front window's folder when nothing is. Finder need not be frontmost.
    static nonisolated func selectionOrFolder() throws -> [URL] {
        let selected = try paths(from: selectionScript)
        return try (selected.isEmpty ? paths(from: folderScript) : selected).map { URL(fileURLWithPath: $0) }
    }

    /// The front window's folder, or the desktop without a window. Finder need not be frontmost.
    static func folder() throws -> URL {
        guard let path = try paths(from: folderScript).first else { throw SelectionError.finderEmpty }
        return URL(fileURLWithPath: path)
    }

    /// The paths a script answers with, one per line.
    private static nonisolated func paths(from script: String) throws -> [String] {
        let execution = AppleScript.execute(script)
        if execution.hasError {
            if execution.isRefused {
                throw SelectionError.automationRefused
            }
            throw SelectionError.finderAutomation(execution.errorMessage ?? String(localized: "The Finder selection couldn't be read.", bundle: .floe))
        }
        return (execution.text ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

/// One snapshot of the general pasteboard, restored only when asked.
nonisolated enum SavedPasteboard {
    struct Snapshot {
        let items: [(types: [NSPasteboard.PasteboardType], dataByType: [NSPasteboard.PasteboardType: Data])]
    }

    static func capture(_ pasteboard: NSPasteboard) -> Snapshot {
        var items: [(types: [NSPasteboard.PasteboardType], dataByType: [NSPasteboard.PasteboardType: Data])] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            items.append((types: item.types, dataByType: dataByType))
        }
        return Snapshot(items: items)
    }
}

nonisolated extension SavedPasteboard.Snapshot {
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        for entry in items {
            let item = NSPasteboardItem()
            for type in entry.types {
                if let data = entry.dataByType[type] {
                    item.setData(data, forType: type)
                }
            }
            pasteboard.writeObjects([item])
        }
    }
}

/// Clipboard content with text, HTML and file, as Raycast's API takes it.
enum PasteboardContent {
    @discardableResult
    static func write(text: String, html: String?, file: String?, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        var wrote = false
        if let file, !file.isEmpty {
            let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
            wrote = pasteboard.writeObjects([url as NSURL]) || wrote
        }
        if let html, !html.isEmpty {
            wrote = pasteboard.setString(html, forType: .html) || wrote
        }
        if !text.isEmpty || !wrote {
            wrote = pasteboard.setString(text, forType: .string) || wrote
        }
        return wrote
    }

    static func read(from pasteboard: NSPasteboard = .general) -> [String: String] {
        var result: [String: String] = ["text": pasteboard.string(forType: .string) ?? ""]
        if let html = pasteboard.string(forType: .html), !html.isEmpty {
            result["html"] = html
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first, first.isFileURL
        {
            result["file"] = first.path
        } else if let fileString = pasteboard.string(forType: .fileURL), !fileString.isEmpty {
            result["file"] = URL(string: fileString)?.path ?? fileString
        }
        return result
    }
}

/// Command keystrokes posted to the frontmost app. Needs Accessibility access to land.
nonisolated enum KeySimulation {
    static func command(keyCode: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Pastes (Command-V) into whatever is frontmost.
    static func paste() {
        command(keyCode: 9)
    }
}
