@testable import Floe
import Foundation
import Testing

@MainActor
@Suite("Editors that run in a terminal")
struct TerminalEditorTests {
    private static let hx = URL(fileURLWithPath: "/opt/homebrew/bin/hx")
    private static let zed = URL(fileURLWithPath: "/Fake/Applications/Zed.app")

    private func mac(programs: [String: URL], flavor: String? = nil) -> AppLookup {
        AppLookup(
            url: { $0 == "dev.zed.Zed" ? Self.zed : nil },
            plainTextApp: { nil },
            exists: { $0 == Self.zed || programs.values.contains($0) },
            bundleIdentifier: { $0 == Self.zed ? "dev.zed.Zed" : nil },
            program: { programs[$0] },
            neovimFlavor: { flavor }
        )
    }

    @Test func helixIsOfferedAsAnEditorWhenItsProgramIsOnThisMac() throws {
        let options = PreferredApps.options(for: .editor, choice: nil, installed: mac(programs: ["hx": Self.hx]))
        #expect(options.map(\.title) == ["Default for Text Files", "Zed", "Helix"])
        let helix = try #require(options.last)
        #expect(helix.choice == AppChoice(bundleIdentifier: nil, path: "/opt/homebrew/bin/hx"))

        let without = PreferredApps.options(for: .editor, choice: nil, installed: mac(programs: [:]))
        #expect(without.map(\.title) == ["Default for Text Files", "Zed"])
        let terminals = PreferredApps.options(for: .terminal, choice: nil, installed: mac(programs: ["hx": Self.hx]))
        #expect(!terminals.map(\.title).contains("Helix"), "it is an editor, not a terminal")
    }

    @Test func aChosenHelixResolvesAndIsNamedHelix() throws {
        let lookup = mac(programs: ["hx": Self.hx])
        let choice = AppChoice(bundleIdentifier: nil, path: Self.hx.path)
        let app = try #require(PreferredApps.app(for: .editor, choice: choice, installed: lookup))
        #expect(app.name == "Helix")
        #expect(PreferredApps.options(for: .editor, choice: choice, installed: lookup).filter { $0.title == "Helix" }.count == 1, "the chosen one is not listed twice")
        #expect(ResolvedApp(url: Self.zed).name == "Zed")
        #expect(ResolvedApp(url: URL(fileURLWithPath: "/usr/local/bin/nvim")).name == "Neovim")
        #expect(ResolvedApp(url: URL(fileURLWithPath: "/Fake/Applications/hx.app")).name == "hx", "an app that happens to be called hx is an app")
    }

    @Test func theEditorsOnThisMacAreListedInAFixedOrderAndNeovimNamesItsDistribution() {
        let nvim = URL(fileURLWithPath: "/opt/homebrew/bin/nvim")
        let programs = ["nano": URL(fileURLWithPath: "/usr/bin/nano"), "nvim": nvim, "vim": URL(fileURLWithPath: "/usr/bin/vim"), "hx": Self.hx]
        let titles = PreferredApps.options(for: .editor, choice: nil, installed: mac(programs: programs, flavor: "LazyVim")).map(\.title)
        #expect(titles == ["Default for Text Files", "Zed", "Helix", "Neovim (LazyVim)", "Vim", "Nano"])
        let plain = PreferredApps.options(for: .editor, choice: nil, installed: mac(programs: ["nvim": nvim])).map(\.title)
        #expect(plain.last == "Neovim")
        let chosen = AppChoice(bundleIdentifier: nil, path: nvim.path)
        let again = PreferredApps.options(for: .editor, choice: chosen, installed: mac(programs: programs, flavor: "LazyVim"))
        #expect(again.filter { $0.choice == chosen }.count == 1, "the flavor is part of the name, not of the choice")
        #expect(Set(TerminalEditor.known.map(\.command)).count == TerminalEditor.known.count)
    }

    @Test func aNeovimConfigurationSaysWhichDistributionItIsBuiltOn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-nvim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func config(_ name: String, files: [String: String]) throws -> URL {
            let folder = root.appendingPathComponent(name)
            for (path, text) in files {
                let file = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
            return folder
        }
        #expect(try TerminalEditor.neovimFlavor(inConfig: config("a", files: ["lazyvim.json": "{}", "init.lua": "require(\"config.lazy\")"])) == "LazyVim")
        #expect(try TerminalEditor.neovimFlavor(inConfig: config("b", files: ["lua/config/lazy.lua": "{ \"LazyVim/LazyVim\", import = \"lazyvim.plugins\" }"])) == "LazyVim")
        #expect(try TerminalEditor.neovimFlavor(inConfig: config("c", files: ["lua/lazy_setup.lua": "{ \"AstroNvim/AstroNvim\", version = \"^5\" }"])) == "AstroNvim")
        #expect(try TerminalEditor.neovimFlavor(inConfig: config("d", files: ["init.lua": "{ \"NvChad/NvChad\", lazy = false }"])) == "NvChad")
        #expect(try TerminalEditor.neovimFlavor(inConfig: config("e", files: ["init.lua": "vim.opt.number = true"])) == nil)
        #expect(TerminalEditor.neovimFlavor(inConfig: root.appendingPathComponent("missing")) == nil)
        #expect(TerminalEditor.neovimConfig(environment: [:]).path.hasSuffix("/.config/nvim"))
        #expect(TerminalEditor.neovimConfig(environment: ["XDG_CONFIG_HOME": "/x", "NVIM_APPNAME": "lazy"]).path == "/x/lazy")
    }

    @Test func aProgramIsRunInTheFolderOfWhatItOpens() {
        #expect(TerminalEditor.isProgram(Self.hx))
        #expect(!TerminalEditor.isProgram(Self.zed))
        let file = URL(fileURLWithPath: "/Users/someone/Projects/floe/main.swift")
        let folder = URL(fileURLWithPath: "/Users/someone/Projects/floe")
        let isFolder: (URL) -> Bool = { $0 == folder }
        #expect(TerminalEditor.commandLine(program: Self.hx, items: [file], isFolder: isFolder)
            == "cd '/Users/someone/Projects/floe' && '/opt/homebrew/bin/hx' '/Users/someone/Projects/floe/main.swift'")
        #expect(TerminalEditor.commandLine(program: Self.hx, items: [folder], isFolder: isFolder)
            == "cd '/Users/someone/Projects/floe' && '/opt/homebrew/bin/hx' '/Users/someone/Projects/floe'")
        let odd = URL(fileURLWithPath: "/tmp/it's here/a b.txt")
        #expect(TerminalEditor.commandLine(program: Self.hx, items: [odd], isFolder: { _ in false })
            == "cd '/tmp/it'\\''s here' && '/opt/homebrew/bin/hx' '/tmp/it'\\''s here/a b.txt'")
        #expect(TerminalEditor.commandLine(program: Self.hx, items: [], isFolder: { _ in false }) == "'/opt/homebrew/bin/hx'")
        let emacs = URL(fileURLWithPath: "/opt/homebrew/bin/emacs")
        #expect(TerminalEditor.commandLine(program: emacs, items: [file], isFolder: isFolder).hasSuffix("&& '/opt/homebrew/bin/emacs' '-nw' '/Users/someone/Projects/floe/main.swift'"), "Emacs stays in the terminal")
    }
}
