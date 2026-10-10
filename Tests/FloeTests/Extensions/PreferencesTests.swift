//
//  PreferencesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

struct CheckboxTextTests {
    /// The preferences of a browser extension as Raycast's manifest has them: one title for the group, a label for each.
    private let browsers = [
        Fixture.field(["name": "enableChrome", "type": "checkbox", "title": "Browsers", "label": "Google Chrome"]),
        Fixture.field(["name": "enableFirefox", "type": "checkbox", "label": "Mozilla Firefox"]),
        Fixture.field(["name": "enableSafari", "type": "checkbox", "title": "", "label": "Safari"]),
    ].compactMap(\.self)

    @Test func theTitleHeadsTheGroupOnceAndEachLabelIsItsCheckboxsText() {
        #expect(browsers.map(\.checkbox.text) == ["Google Chrome", "Mozilla Firefox", "Safari"])
        #expect(browsers.map(\.checkbox.heading) == ["Browsers", nil, nil], "the ones after the titled one sit under its heading")
        #expect(browsers.map(\.displayTitle) == ["Google Chrome", "Mozilla Firefox", "Safari"], "the internal name is never what a checkbox is called")
    }

    @Test func aCheckboxWithOnlyATitleShowsItBesideTheBoxWithNoHeading() throws {
        let field = try #require(Fixture.field(["name": "favicon", "type": "checkbox", "title": "Show Favicons"]))
        #expect(field.checkbox.text == "Show Favicons")
        #expect(field.checkbox.heading == nil)
        #expect(CheckboxText.parts(title: "Show Favicons", label: "").text == "Show Favicons", "an empty label is no label")
    }

    @Test func onlyACheckboxWithNeitherFallsBackToItsName() throws {
        let bare = try #require(Fixture.field(["name": "verbose", "type": "checkbox"]))
        #expect(bare.checkbox.text == "verbose")
        #expect(bare.checkbox.heading == nil)
        #expect(CheckboxText.parts(title: nil, label: nil).text.isEmpty, "a form's checkbox has no name to fall back to")
    }

    @Test func anExtensionsFormCheckboxSplitsTheSameWay() {
        let both = CheckboxText.parts(title: "User Interface", label: "Favicon")
        #expect(both.heading == "User Interface")
        #expect(both.text == "Favicon")
    }

    @Test func otherFieldsKeepTheirTitleAndFallBackAsBefore() throws {
        let titled = try #require(Fixture.field(["name": "apiToken", "type": "password", "title": "API Token"]))
        #expect(titled.displayTitle == "API Token")
        #expect(Fixture.field("region").displayTitle == "region")
        #expect(Fixture.field(["name": "query", "placeholder": "Search"])?.displayTitle == "Search")
    }
}

struct FieldValuesTests {
    @Test func checkboxesEditAsTrueOrFalseAndEverythingElseAsText() {
        #expect(FieldValues.text(from: true) == "true")
        #expect(FieldValues.text(from: false) == "false")
        #expect(FieldValues.text(from: "plain") == "plain")
        #expect(FieldValues.text(from: 5) == "5")
    }

    @Test func anEditorStartsWithTheStoredValueThenTheDefaultThenTheFirstOption() {
        let dropdown = Fixture.field("region", type: "dropdown", options: [("Europe", "eu"), ("Americas", "us")])
        let withDefault = Fixture.field("region", type: "dropdown", defaultValue: "us", options: [("Europe", "eu"), ("Americas", "us")])
        #expect(FieldValues.initialText(for: withDefault, stored: "eu") == "eu")
        #expect(FieldValues.initialText(for: withDefault, stored: nil) == "us")
        #expect(FieldValues.initialText(for: dropdown, stored: nil) == "eu")
        #expect(FieldValues.initialText(for: Fixture.field("name"), stored: nil) == "")
        #expect(FieldValues.initialText(for: Fixture.field("shout", type: "checkbox", defaultValue: true), stored: nil) == "true")
    }

    @Test func typedValuesTurnCheckboxTextBackIntoBooleans() {
        let fields = [Fixture.field("name"), Fixture.field("shout", type: "checkbox"), Fixture.field("quiet", type: "checkbox"), Fixture.field("unset")]
        let typed = FieldValues.typed(["name": "Ada", "shout": "true", "quiet": "false", "extra": "ignored"], fields: fields)
        #expect(typed["name"] as? String == "Ada")
        #expect(typed["shout"] as? Bool == true)
        #expect(typed["quiet"] as? Bool == false)
        #expect(typed["unset"] as? String == "")
        #expect(typed["extra"] == nil)
    }

    @Test func missingListsRequiredFieldsThatAreStillEmpty() {
        let fields = [
            Fixture.field("token", type: "password", required: true),
            Fixture.field("name", required: true),
            Fixture.field("optional"),
            Fixture.field("agree", type: "checkbox", required: true),
        ]
        #expect(FieldValues.missing(fields, texts: ["name": "Ada"]).map(\.name) == ["token"])
        #expect(FieldValues.missing(fields, texts: ["token": "", "name": ""]).map(\.name) == ["token", "name"])
        #expect(FieldValues.missing(fields, texts: ["token": "t", "name": "n"]).isEmpty, "a required checkbox always has a value")
    }
}

struct PreferenceResolverTests {
    private let extensionFields = [
        Fixture.field("greeting", required: true),
        Fixture.field("token", type: "password"),
        Fixture.field("shout", type: "checkbox"),
        Fixture.field("units", type: "dropdown", defaultValue: "metric"),
    ]
    private let commandFields = [Fixture.field("days", defaultValue: "3"), Fixture.field("greeting")]

    private func resolve(stored: [String: Any] = [:], secrets: [String: String] = [:]) -> [String: Any] {
        PreferenceResolver.resolve(
            extensionFields: extensionFields,
            commandFields: commandFields,
            commandName: "forecast",
            stored: stored,
            secret: { secrets[$0] }
        )
    }

    @Test func commandPreferencesAreStoredUnderTheCommandsName() {
        #expect(PreferenceResolver.storageKey(Fixture.field("days"), commandName: "forecast") == "forecast/days")
        #expect(PreferenceResolver.storageKey(Fixture.field("days"), commandName: nil) == "days")
    }

    @Test func withNothingStoredDefaultsApplyAndCheckboxesAreFalse() {
        let values = resolve()
        #expect(values["units"] as? String == "metric")
        #expect(values["days"] as? String == "3")
        #expect(values["shout"] as? Bool == false)
        #expect(values["greeting"] == nil)
        #expect(values["token"] == nil)
    }

    @Test func storedValuesOverrideDefaults() {
        let values = resolve(stored: ["units": "imperial", "shout": true, "forecast/days": "7"])
        #expect(values["units"] as? String == "imperial")
        #expect(values["shout"] as? Bool == true)
        #expect(values["days"] as? String == "7")
    }

    @Test func passwordsComeFromTheSecretLookupNotTheStoredFile() {
        #expect(resolve(stored: ["token": "from-file"])["token"] == nil)
        #expect(resolve(secrets: ["token": "from-keychain"])["token"] as? String == "from-keychain")
    }

    @Test func aCommandPreferenceWithTheSameNameWinsOverTheExtensions() {
        #expect(resolve(stored: ["greeting": "Hello", "forecast/greeting": "Hi"])["greeting"] as? String == "Hi")
        #expect(resolve(stored: ["greeting": "Hello"])["greeting"] as? String == "Hello")
    }

    @Test func aValueStoredForAnotherCommandIsNotUsed() {
        #expect(resolve(stored: ["other/days": "9"])["days"] as? String == "3")
    }

    @Test func requiredFieldsWithoutAValueOrWithAnEmptyOneAreMissing() {
        let fields = extensionFields + commandFields
        #expect(PreferenceResolver.missingRequired(fields, values: resolve()).map(\.name) == ["greeting"])
        #expect(PreferenceResolver.missingRequired(fields, values: ["greeting": ""]).map(\.name) == ["greeting"])
        #expect(PreferenceResolver.missingRequired(fields, values: ["greeting": "Hello"]).isEmpty)
        #expect(PreferenceResolver.missingRequired([Fixture.field("on", type: "checkbox", required: true)], values: ["on": false]).isEmpty)
    }
}
