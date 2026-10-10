//
//  AppRole.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A kind of app the user has a preferred one of. Floe hands things to that app and does none of its work.
enum AppRole: String, CaseIterable, Identifiable {
    case terminal
    case editor
    case browser
    case notes
    case clipboard

    /// What a role's app is handed.
    enum Input {
        /// A folder; a file stands for the folder it is in.
        case folder
        case fileOrFolder
        /// Text typed into the search, sent through a link or a script the app answers (see `Notes`).
        case text
        /// A web link, one at a time (see `Browsers`).
        case link
        /// Nothing: the app is opened to show what it already has (see `ClipboardApps`).
        case nothing
    }

    var id: String {
        rawValue
    }

    /// The role's name in Settings.
    var title: String {
        switch self {
        case .terminal: String(localized: "Terminal", bundle: .floe, comment: "The kind of app that runs a shell, as the label of the picker that chooses one.")
        case .editor: String(localized: "Editor", bundle: .floe, comment: "The kind of app that edits text files, as the label of the picker that chooses one.")
        case .browser: String(localized: "Browser", bundle: .floe, comment: "The kind of app that opens web pages, as the label of the picker that chooses one.")
        case .notes: String(localized: "Notes", bundle: .floe, comment: "The kind of app that keeps notes, as the label of the picker that chooses one.")
        case .clipboard: String(localized: "Clipboard", bundle: .floe, comment: "The kind of app that keeps a clipboard history, as the label of the picker that chooses one.")
        }
    }

    var input: Input {
        switch self {
        case .terminal: .folder
        case .editor: .fileOrFolder
        case .browser: .link
        case .notes: .text
        case .clipboard: .nothing
        }
    }

    /// The line under the role's picker in Settings.
    var detail: String {
        switch self {
        case .terminal: String(localized: "Opens a folder from the Actions menu or from Finder, and the SSH hosts you pick in the search.", bundle: .floe)
        case .editor: String(localized: "Opens a file or a folder from the Actions menu or from Finder.", bundle: .floe)
        case .browser: String(localized: "Opens web addresses, quicklinks and the other web links you open from Floe.", bundle: .floe)
        case .notes: String(localized: "Type “note” and then your text in the search to send it there.", bundle: .floe, comment: "The word in quotation marks is typed as it is and stays in English.")
        case .clipboard: String(localized: "Opens from Clipboard History in the search. With another app chosen, Floe saves no copies and keeps the history it has.", bundle: .floe)
        }
    }

    /// The terminal every Mac has, which the terminal role uses until another is chosen.
    static nonisolated let systemTerminal = "com.apple.Terminal"

    /// Bundle identifiers of the apps offered by name when they are installed. Each one was read from
    /// the Info.plist of an installed copy; an app that is not here is picked with Choose.
    var knownApps: [String] {
        switch self {
        case .terminal: ["com.mitchellh.ghostty"]
        case .editor: ["com.apple.TextEdit", "com.microsoft.VSCode", "dev.zed.Zed", "com.apple.dt.Xcode"]
        // The browsers are read from the system when the picker is shown (see `Browsers`).
        case .browser: []
        // Notes go to an app Floe knows how to hand text to, which `NotesApp` lists.
        case .notes: []
        // Raycast's history opens from a link, which `ClipboardApps.links` holds.
        case .clipboard: ["com.raycast.macos"]
        }
    }

    /// Other words the role's search rows answer to.
    var keywords: [String] {
        let terms = switch self {
        case .terminal: String(localized: "terminal, shell, command line, finder selection", bundle: .floe, comment: "Words that find the rows of the terminal app in the search, separated by commas.")
        case .editor: String(localized: "editor, edit, code, finder selection", bundle: .floe, comment: "Words that find the rows of the editor app in the search, separated by commas.")
        case .browser: String(localized: "browser, web, links", bundle: .floe, comment: "Words that find the rows of the browser app in the search, separated by commas.")
        case .notes: String(localized: "notes, jot, memo", bundle: .floe, comment: "Words that find the rows of the notes app in the search, separated by commas.")
        case .clipboard: String(localized: "clipboard, copies, paste", bundle: .floe, comment: "Words that find the rows of the clipboard app in the search, separated by commas.")
        }
        return terms.searchTerms
    }

    /// How the picker names the choice of nothing, given the app that stands in for it.
    func defaultTitle(appName: String?) -> String {
        switch self {
        case .terminal: appName ?? "Terminal"
        case .editor:
            appName.map { String(localized: "Default for Text Files (\($0))", bundle: .floe, comment: "The placeholder is the name of an app.") }
                ?? String(localized: "Default for Text Files", bundle: .floe)
        case .browser:
            appName.map { String(localized: "Default Browser (\($0))", bundle: .floe, comment: "The placeholder is the name of an app.") }
                ?? String(localized: "Default Browser", bundle: .floe)
        case .notes: NotesApp.appleNotes.title
        case .clipboard: "Floe"
        }
    }

    /// The roles whose app is handed files and folders.
    static var opening: [AppRole] {
        allCases.filter { $0.input == .folder || $0.input == .fileOrFolder }
    }
}

/// The app chosen for a role: its bundle identifier, so a moved or updated copy still resolves,
/// and the path it was picked at for an app without one.
struct AppChoice: Codable, Hashable {
    var bundleIdentifier: String?
    var path: String

    /// What tells one choice from another whatever folder the app is in now.
    var key: String {
        bundleIdentifier ?? path
    }
}

/// An application on this Mac, named as its bundle is.
nonisolated struct ResolvedApp: Hashable {
    let url: URL

    var name: String {
        TerminalEditor.at(url)?.title ?? url.deletingPathExtension().lastPathComponent
    }
}

/// A role with the app it resolves to right now.
struct RoleApp: Hashable {
    let role: AppRole
    let app: ResolvedApp
}
