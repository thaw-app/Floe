//
//  SetupFormModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// Argument forms only: a preferences form reads what is stored for the extension.
@MainActor
struct SetupFormModelTests {
    private func command(_ arguments: [FieldSpec]) -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/floe-setup-form-tests"), extensionName: "floe-setup-form-tests",
            extensionTitle: "Tests", source: .local, name: "greet", title: "Greet",
            mode: "view", interval: nil, icon: nil, arguments: arguments, extensionPreferences: [], commandPreferences: []
        )
    }

    private func request(_ fields: [FieldSpec]) -> SetupRequest {
        SetupRequest(command: command(fields), kind: .arguments, fields: fields)
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func aFormStartsOnItsFieldsDefaultsWithNoError() {
        let form = SetupFormModel()
        let fields = [Fixture.field("name", required: true), Fixture.field("greeting", defaultValue: "Hello"), Fixture.field("loud", type: "checkbox")]
        form.values = ["left": "over"]
        form.begin(request(fields))
        #expect(form.values == ["name": "", "greeting": "Hello", "loud": ""], "a checkbox with no default starts unset")
        #expect(form.error == nil)
    }

    @Test func aMissingRequiredFieldIsNamedAndFillingItInGivesTheTypedValues() throws {
        let form = SetupFormModel()
        let request = request([Fixture.field("name", required: true), Fixture.field("loud", type: "checkbox")])
        form.begin(request)
        #expect(form.validated(for: request) == nil)
        #expect(form.error == "Fill in name.")

        form.values["name"] = "Ada"
        form.values["loud"] = "true"
        let values = try #require(form.validated(for: request))
        #expect(values["name"] as? String == "Ada")
        #expect(values["loud"] as? Bool == true)

        form.begin(request)
        #expect(form.error == nil, "a form that is opened again starts clean")
    }

    @Test func theLauncherShowsTheFormAndTypingInItDoesNotRepublishTheLauncher() throws {
        let settings = AppSettings(defaults: MemoryDefaults())
        let greet = command([Fixture.field("name", required: true)])
        let launcher = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [greet]), scopes: [], sources: [])
        launcher.runner.run(greet)
        #expect(launcher.setup?.kind == .arguments)
        #expect(launcher.setupForm.values == ["name": ""])
        #expect(launcher.panelState.isRootSearch == false)

        var changes = 0
        let subscription = launcher.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        launcher.setupForm.values["name"] = ""
        #expect(try launcher.handleKey(key(36)), "Return with the field still empty")
        #expect(launcher.setupForm.error == "Fill in name.")
        #expect(launcher.setup != nil, "the form stays")
        #expect(changes == 0)

        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.setup == nil)
        #expect(launcher.runner.session == nil, "the command did not run")
    }

    private func notion(_ fields: [FieldSpec]) -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/floe-setup-form-tests"), extensionName: "floe-setup-form-tests",
            extensionTitle: "Notion", source: .local, name: "search", title: "Search Notion",
            mode: "view", interval: nil, icon: nil, arguments: [], extensionPreferences: fields, commandPreferences: []
        )
    }

    @Test func aFormThatStandsInForASignInNeedsItsFieldThoughTheExtensionDoesNot() {
        let token = Fixture.field("token", type: "password")
        let ordinary = SetupRequest(command: notion([token]), kind: .preferences, fields: [token])
        #expect(ordinary.missing(in: ["token": ""]).isEmpty)
        let signIn = SetupRequest(command: notion([token]), kind: .preferences, fields: [token], provider: "Notion")
        #expect(signIn.missing(in: ["token": ""]).map(\.name) == ["token"])
        #expect(signIn.missing(in: ["token": "secret_abc"]).isEmpty)
    }

    @Test func savingAFormTouchesOnlyTheFieldsItAskedFor() {
        let declared = [Fixture.field("token", type: "password"), Fixture.field("open_in"), Fixture.field("other", type: "password")]
        let request = SetupRequest(command: notion(declared), kind: .preferences, fields: [declared[0]], provider: "Notion")
        #expect(request.asked(of: declared).map(\.name) == ["token"])
        #expect(request.asked(of: [declared[1]]).isEmpty)
        let whole = SetupRequest(command: notion(declared), kind: .preferences, fields: declared)
        #expect(whole.asked(of: declared).map(\.name) == ["token", "open_in", "other"])
    }

    @Test func aCommandThatAsksToSignInGetsAFormForItsTokenAndIsEnded() throws {
        let settings = AppSettings(defaults: MemoryDefaults())
        let search = notion([Fixture.field("token", type: "password"), Fixture.field("open_in")])
        let launcher = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [search]), scopes: [], sources: [])
        let session = ExtensionSession(command: search, arguments: ["query": "notes"])

        launcher.runner.handle(["type": "signIn", "preference": "nothing-by-this-name", "provider": "Notion"], from: session)
        #expect(launcher.setup == nil, "a preference the command does not declare asks for nothing")

        launcher.runner.handle(["type": "signIn", "preference": "token", "provider": "Notion"], from: session)
        let setup = try #require(launcher.setup)
        #expect(setup.kind == .preferences)
        #expect(setup.fields.map(\.name) == ["token"])
        #expect(setup.provider == "Notion")
        #expect(setup.arguments?["query"] as? String == "notes")
        #expect(launcher.runner.session == nil)

        #expect(try launcher.handleKey(key(36)), "Return with the token still empty")
        #expect(launcher.setupForm.error == "Fill in token.")
        #expect(launcher.setup != nil, "the form stays")
        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.setup == nil)
    }
}
