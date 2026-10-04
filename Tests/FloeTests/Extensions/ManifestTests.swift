//
//  ManifestTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct FieldSpecTests {
    @Test func readsEveryManifestKey() throws {
        let field = try #require(Fixture.field([
            "name": "region", "title": "Region", "description": "Where to search", "type": "dropdown", "required": true,
            "placeholder": "Pick one", "label": "Unused", "default": "eu",
            "data": [["title": "Europe", "value": "eu"], ["value": "us"], ["title": "No value"]],
        ]))
        #expect(field.name == "region")
        #expect(field.id == "region")
        #expect(field.title == "Region")
        #expect(field.detail == "Where to search")
        #expect(field.type == "dropdown")
        #expect(field.required)
        #expect(field.placeholder == "Pick one")
        #expect(field.label == "Unused")
        #expect(field.defaultValue as? String == "eu")
        #expect(field.options.map(\.title) == ["Europe", "us"], "an option without a title uses its value; one without a value is dropped")
        #expect(field.options.map(\.value) == ["eu", "us"])
    }

    @Test func defaultsToAnOptionalTextField() throws {
        let field = try #require(Fixture.field(["name": "query"]))
        #expect(field.type == "textfield")
        #expect(field.required == false)
        #expect(field.title == "query")
        #expect(field.options.isEmpty)
        #expect(field.defaultValue == nil)
    }

    @Test(arguments: [
        ["name": "x", "default": true],
        ["name": "x", "default": "eu"],
        ["name": "x", "default": 5],
        ["name": "x", "default": 1.5],
    ] as [[String: any Sendable]])
    func scalarDefaultsSurviveTheRoundTrip(json: [String: any Sendable]) throws {
        let decoded = try #require(Fixture.field(json))
        #expect(decoded.defaultValue != nil)
        #expect(decoded.defaultValue as? Bool == json["default"] as? Bool)
        #expect(decoded.defaultValue as? String == json["default"] as? String)
        #expect(decoded.defaultValue as? Int == json["default"] as? Int)
        #expect(decoded.defaultValue as? Double == json["default"] as? Double)
    }

    @Test func aWholeNumberDefaultStaysAnIntAndAFractionBecomesADouble() {
        #expect(Fixture.field(["name": "x", "default": 5])?.defaultValue as? Int == 5)
        #expect(Fixture.field(["name": "x", "default": 5])?.defaultValue as? Double == nil)
        #expect(Fixture.field(["name": "x", "default": 1.5])?.defaultValue as? Double == 1.5)
        #expect(Fixture.field(["name": "x", "default": 1.5])?.defaultValue as? Int == nil)
    }

    @Test func defaultsOfUnsupportedTypesBecomeNil() {
        #expect(Fixture.field(["name": "x", "default": ["structured"]])?.defaultValue == nil)
        #expect(Fixture.field(["name": "x", "default": ["nested": 1]])?.defaultValue == nil)
    }

    @Test func argumentsUseTheirPlaceholderAsTitle() throws {
        let field = try #require(Fixture.field(["name": "text", "placeholder": "Text"]))
        #expect(field.title == "Text")
    }

    @Test func aFieldNeedsAName() {
        #expect(Fixture.field(["title": "Nameless"]) == nil)
    }

    @Test(arguments: [("password", true), ("textfield", false), ("checkbox", false)])
    func onlyPasswordsAreSecret(type: String, secret: Bool) throws {
        let field = try #require(Fixture.field(["name": "value", "type": type]))
        #expect(field.isSecret == secret)
    }
}

struct ExtensionCommandTests {
    private let folder = URL(fileURLWithPath: "/tmp/extensions/weather")

    private let manifest: [String: Any] = [
        "name": "weather", "title": "Weather", "icon": "icon.png",
        "preferences": [["name": "units", "type": "dropdown"]],
        "commands": [
            [
                "name": "forecast",
                "title": "Forecast",
                "mode": "view",
                "icon": "forecast.png",
                "arguments": [["name": "city", "type": "text"]],
                "preferences": [["name": "days"]],
            ],
            ["name": "refresh", "mode": "no-view"],
            ["name": "status", "mode": "menu-bar"],
            ["name": "plain"],
            ["title": "No name"],
        ],
    ]

    @Test func listsViewNoViewAndMenuBarCommands() {
        let commands = ExtensionCommand.commands(inManifest: Fixture.manifest(manifest), folder: folder, source: .raycast)
        #expect(commands.map(\.name) == ["forecast", "refresh", "status", "plain"], "nameless entries are skipped")
        #expect(commands.map(\.mode) == ["view", "no-view", "menu-bar", "view"], "a command without a mode is a view")
    }

    @Test func commandsCarryExtensionAndCommandDetails() throws {
        let forecast = try #require(ExtensionCommand.commands(inManifest: Fixture.manifest(manifest), folder: folder, source: .raycast).first)
        #expect(forecast.id == "weather/forecast")
        #expect(forecast.extensionName == "weather")
        #expect(forecast.extensionTitle == "Weather")
        #expect(forecast.title == "Forecast")
        #expect(forecast.icon == "forecast.png")
        #expect(forecast.source == .raycast)
        #expect(forecast.assetsPath == "/tmp/extensions/weather/assets")
        #expect(forecast.arguments.map(\.name) == ["city"])
        #expect(forecast.extensionPreferences.map(\.name) == ["units"])
        #expect(forecast.commandPreferences.map(\.name) == ["days"])
        #expect(forecast.preferences.map(\.name) == ["units", "days"])
    }

    @Test func commandFallsBackToItsNameAndTheExtensionIcon() throws {
        let commands = ExtensionCommand.commands(inManifest: Fixture.manifest(manifest), folder: folder, source: .local)
        let refresh = try #require(commands.first { $0.name == "refresh" })
        #expect(refresh.title == "refresh")
        #expect(refresh.icon == "icon.png")
        #expect(refresh.arguments.isEmpty)
    }

    @Test func extensionTitleFallsBackToItsName() throws {
        let command = try #require(ExtensionCommand.commands(
            inManifest: Fixture.manifest(["name": "bare", "commands": [["name": "run"]]]),
            folder: folder,
            source: .local
        ).first)
        #expect(command.extensionTitle == "bare")
    }

    @Test(arguments: [[:], ["name": "no-commands"], ["commands": [["name": "run"]]]] as [[String: any Sendable]])
    func manifestsWithoutANameOrCommandsYieldNothing(manifest: [String: any Sendable]) {
        #expect(ExtensionCommand.commands(inManifest: Fixture.manifest(manifest), folder: folder, source: .local).isEmpty)
    }

    @Test func scansAFolderOfExtensionsInNameOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, manifest) in [
            ("zeta", #"{"name":"zeta","commands":[{"name":"z"}]}"#),
            ("alpha", #"{"name":"alpha","commands":[{"name":"a"},{"name":"b","mode":"no-view"}]}"#),
            ("broken", "not json"),
        ] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try manifest.write(to: folder.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("no-manifest"), withIntermediateDirectories: true)

        let commands = ExtensionCommand.scan(root: root, source: .local)
        #expect(commands.map(\.id) == ["alpha/a", "alpha/b", "zeta/z"])
        #expect(ExtensionCommand.scan(root: root.appendingPathComponent("missing"), source: .local).isEmpty)
    }
}

struct RootItemTests {
    private let command = Fixture.command("frontpage", extension: "hacker-news", title: "Hacker News")

    @Test func identifiersAreStableAndDistinctPerKind() {
        #expect(Fixture.app("Safari").id == "app:/Applications/Safari.app")
        #expect(RootItem.command(command).id == "command:hacker-news/frontpage")
        #expect(RootItem.menuBarSearch.id == "builtin:menubar-search")
        #expect(RootItem.settings.id == "settings")
        #expect(RootItem.calculator(expression: "2 + 2", result: "4").id == "calculator")
    }

    @Test func titlesSubtitlesAndKinds() {
        #expect(Fixture.app("Safari").title == "Safari")
        #expect(Fixture.app("Safari").subtitle == nil)
        #expect(Fixture.app("Safari").kind == "Application")
        #expect(RootItem.command(command).title == "Hacker News")
        #expect(RootItem.command(command).subtitle == "Hacker-News")
        #expect(RootItem.command(command).kind == "Command")
        #expect(RootItem.menuBarSearch.title == "Search Menu Bar Items")
        #expect(RootItem.menuBarSearch.kind == "Floe")
        #expect(RootItem.settings.title == "Floe Settings")
        #expect(RootItem.settings.kind == "Floe")
        #expect(RootItem.calculator(expression: "2 + 2", result: "4").title == "4")
        #expect(RootItem.calculator(expression: "2 + 2", result: "4").subtitle == nil)
        #expect(RootItem.calculator(expression: "2 + 2", result: "4").kind == "Calculator")
    }

    @Test func settingsKeysCoverEverythingThatCanHaveAnAliasOrHotkey() {
        #expect(Fixture.app("Safari").settingsKey == "app:/Applications/Safari.app")
        #expect(RootItem.command(command).settingsKey == "hacker-news/frontpage", "commands keep the key used before apps had one")
        #expect(RootItem.menuBarSearch.settingsKey == RootItem.menuBarSearchKey)
        #expect(RootItem.settings.settingsKey == nil)
        #expect(RootItem.calculator(expression: "2 + 2", result: "4").settingsKey == nil)
    }

    @Test func onlyAppsAreApps() {
        #expect(Fixture.app("Safari").isApp)
        #expect(RootItem.command(command).isApp == false)
        #expect(RootItem.settings.isApp == false)
        #expect(RootItem.calculator(expression: "2 + 2", result: "4").isApp == false)
    }

    @Test func resultsTakeTheirIdentifierFromTheItem() {
        #expect(RootResult(item: .settings, section: "Commands").id == "settings")
        #expect(RootResult(item: .calculator(expression: "2 + 2", result: "4"), section: nil).id == "calculator")
    }
}
