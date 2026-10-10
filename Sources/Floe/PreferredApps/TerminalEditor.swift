//
//  TerminalEditor.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// An editor that is a program run in a terminal and not an app. Floe opens files with it in the terminal the user chose.
nonisolated struct TerminalEditor: Equatable {
    let title: String
    let command: String
    /// What the program needs to stay in the terminal: Emacs opens a window of its own without `-nw`.
    var arguments: [String] = []

    /// Offered by name when the program is on this Mac. Vim and Nano come with macOS, so they are always there.
    static let known = [
        TerminalEditor(title: "Helix", command: "hx"),
        TerminalEditor(title: "Neovim", command: "nvim"),
        TerminalEditor(title: "LunarVim", command: "lvim"),
        TerminalEditor(title: "Vim", command: "vim"),
        TerminalEditor(title: "Emacs", command: "emacs", arguments: ["-nw"]),
        TerminalEditor(title: "Kakoune", command: "kak"),
        TerminalEditor(title: "Micro", command: "micro"),
        TerminalEditor(title: "Nano", command: "nano"),
    ]

    static let neovim = "nvim"

    /// The distribution a Neovim configuration is built on, read from the files each one leaves. Nil for a plain one.
    static func neovimFlavor(inConfig folder: URL) -> String? {
        let files = FileManager.default
        if files.fileExists(atPath: folder.appendingPathComponent("lazyvim.json").path) {
            return "LazyVim"
        }
        let marks = ["LazyVim/LazyVim": "LazyVim", "AstroNvim/AstroNvim": "AstroNvim", "NvChad/NvChad": "NvChad"]
        for name in ["init.lua", "lua/config/lazy.lua", "lua/lazy_setup.lua", "lua/plugins/init.lua"] {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { continue }
            if let found = marks.first(where: { text.contains($0.key) }) {
                return found.value
            }
        }
        return nil
    }

    /// Where Neovim reads its configuration from.
    static func neovimConfig(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base = environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        return base.appendingPathComponent(environment["NVIM_APPNAME"] ?? "nvim")
    }

    static func at(_ url: URL) -> TerminalEditor? {
        isProgram(url) ? known.first { $0.command == url.lastPathComponent } : nil
    }

    /// Whether what was chosen is a program to run, where an app is a bundle to open.
    static func isProgram(_ url: URL) -> Bool {
        url.pathExtension != "app"
    }

    /// The command that opens the items, run in the folder of the first so the editor's own file picker starts there.
    static func commandLine(program: URL, items: [URL], isFolder: (URL) -> Bool) -> String {
        guard let first = items.first else { return quoted(program.path) }
        let folder = isFolder(first) ? first : first.deletingLastPathComponent()
        let words = [program.path] + (at(program)?.arguments ?? []) + items.map(\.path)
        return "cd \(quoted(folder.path)) && " + words.map(quoted).joined(separator: " ")
    }

    /// One argument for the shell, whatever is in it.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
