//
//  RaycastImportFlow+Live.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import AppKit
import UniformTypeIdentifiers

extension RaycastImportFlow.Environment {
    /// Panels and alerts of the settings process, and the apps in the usual folders.
    static var live: Self {
        let installed = InstalledAppsOnce()
        return Self(
            chooseFile: chooseFile,
            askPassphrase: askPassphrase,
            read: read,
            apps: QuicklinkImport.Apps(home: FileManager.default.homeDirectoryForCurrentUser) { installed.app(named: $0) },
            tell: { title, detail in
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = detail
                alert.runModal()
            }
        )
    }

    private static func chooseFile() -> URL? {
        ModalGuard.run {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json, UTType(filenameExtension: "rayconfig") ?? .data]
            panel.allowsMultipleSelection = false
            panel.message = String(localized: "Choose a Raycast quicklinks export or a .rayconfig backup.", bundle: .floe)
            return panel.runModal() == .OK ? panel.url : nil
        }
    }

    private static func askPassphrase(again: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = again
            ? String(localized: "That passphrase didn't open the backup", bundle: .floe)
            : String(localized: "Enter the backup's passphrase", bundle: .floe)
        alert.informativeText = String(localized: "The passphrase Raycast showed when it exported the backup. It's used once and not saved.", bundle: .floe)
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Import", bundle: .floe, comment: "The button that imports quicklinks from a Raycast backup."))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .floe))
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// The file may be large or on a slow disk, and a backup runs scrypt: both off the main actor.
    @concurrent
    private static func read(_ file: URL, passphrase: String?) async -> RaycastExport.Reading {
        guard let data = try? Data(contentsOf: file) else { return .notAnExport }
        return RaycastExport.read(data, passphrase: passphrase)
    }
}

/// The apps in the usual folders, listed the first time an imported link names one and kept for the rest of the import.
private final class InstalledAppsOnce {
    private lazy var apps = InstalledApps.list()

    func app(named name: String) -> AppChoice? {
        InstalledApps.choice(named: name, among: apps)
    }
}
