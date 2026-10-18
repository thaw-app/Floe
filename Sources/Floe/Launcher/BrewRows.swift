//
//  BrewRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Homebrew packages the search found: Return installs or upgrades one in the terminal.
final class BrewRows {
    var host = RowHost()
    /// Runs a command in the terminal the role says, where it shows what it does and asks for a password.
    var runInTerminal: (String) -> Void = { _ in }
    /// Where a name is copied to. Tests replace it, so they leave the clipboard alone.
    var pasteboard = NSPasteboard.general
    static func title(for verb: Homebrew.Verb) -> String {
        switch verb {
        case .install: String(localized: "Install in Terminal", bundle: .floe, comment: "A button that runs the command installing a Homebrew package in the terminal.")
        case .upgrade: String(localized: "Upgrade in Terminal", bundle: .floe, comment: "A button that runs the command upgrading a Homebrew package in the terminal.")
        case .uninstall: String(localized: "Uninstall in Terminal", bundle: .floe, comment: "A button that runs the command removing a Homebrew package in the terminal.")
        }
    }

    /// Hands the command to the terminal: there it shows what it does and asks for a password when it needs one.
    func brew(_ verb: Homebrew.Verb, _ package: BrewPackage) {
        runInTerminal(Homebrew.command(verb, package))
    }

    func brewActions(for package: BrewPackage) -> [ItemAction?] {
        var actions: [ItemAction?] = [nil]
        if package.isInstalled {
            actions.append(ItemAction(title: Self.title(for: .uninstall), symbol: "trash") { [weak self] in self?.brew(.uninstall, package) })
        }
        actions.append(ItemAction(title: String(localized: "Copy Name", bundle: .floe, comment: "A button that copies the name of the selected thing."), symbol: "doc.on.doc") { [weak self] in
            self?.pasteboard.copy(package.name)
            self?.host.showHUD(String(localized: "Copied \(package.name)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
        })
        return actions
    }
}

extension BrewRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case let .brew(package) = item else { return nil }
        return Self.title(for: Homebrew.primaryVerb(for: package))
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .brew(package) = item else { return false }
        brew(Homebrew.primaryVerb(for: package), package)
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .brew(package) = item else { return nil }
        return brewActions(for: package)
    }
}
