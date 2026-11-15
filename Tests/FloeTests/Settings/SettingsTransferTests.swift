//
//  SettingsTransferTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SettingsTransferTests {
    private func archive() -> SettingsTransfer.Archive {
        SettingsTransfer.Archive(
            settings: Data(#"{"aliases":{"a":"x","b":"y"},"favorites":["one"],"commandHotkeys":{"c":{}}}"#.utf8),
            preferences: ["weather": ["unit": "metric", "days": 3]],
            secretKeys: ["github": ["token"], "weather": ["apiKey"]]
        )
    }

    @Test func anExportReadsBackTheSame() throws {
        let decoded = try SettingsTransfer.decode(SettingsTransfer.encode(archive()))
        #expect(decoded.preferences["weather"]?["unit"] as? String == "metric")
        #expect(decoded.preferences["weather"]?["days"] as? Int == 3)
        #expect(decoded.secretKeys == ["github": ["token"], "weather": ["apiKey"]])
    }

    @Test func aFileWithoutSecretKeysStillLoads() throws {
        let decoded = try SettingsTransfer.decode(Data(#"{"version":1,"settings":{}}"#.utf8))
        #expect(decoded.secretKeys.isEmpty)
        #expect(decoded.preferences.isEmpty)
    }

    @Test func aNewerFileAndAnyOtherJSONAreRefused() {
        #expect(throws: SettingsTransfer.TransferError.newerVersion(2)) {
            try SettingsTransfer.decode(Data(#"{"version":2,"settings":{}}"#.utf8))
        }
        #expect(throws: SettingsTransfer.TransferError.notAnExport) {
            try SettingsTransfer.decode(Data(#"{"name":"package"}"#.utf8))
        }
    }

    @Test func theSummaryCountsWhatCameAndListsPasswordsToEnterAgain() {
        let summary = SettingsTransfer.summary(of: archive()) { name, _ in name == "weather" }
        #expect(summary == SettingsTransfer.Summary(aliases: 2, hotkeys: 1, favorites: 1, extensions: 1, missingSecrets: ["github: token"]))
    }
}

struct SettingsImportTests {
    /// A file with every consent given and the promise to keep AI here dropped.
    private func generousFile() throws -> Data {
        let file = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        file.lentSignIns = ["stealer/github"]
        file.shellEnvironmentExtensions = ["stealer"]
        file.searchSources = ["files", "tabs"]
        file.indexesFileNames = true
        file.fetchesExchangeRates = true
        file.syncsWithICloud = true
        file.shell.runs = true
        file.shell.prefix = .dollar
        file.aiOnThisMacOnly = false
        file.aliases = ["sample/planets": "p"]
        return try file.exportedJSON()
    }

    @Test func anImportKeepsTheConsentGivenOnThisMac() throws {
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        here.lentSignIns = ["mine/gitlab"]
        here.searchSources = ["files"]
        here.aiOnThisMacOnly = true
        here.shell.runs = false

        try here.importJSON(generousFile())

        #expect(here.lentSignIns == ["mine/gitlab"])
        #expect(here.shellEnvironmentExtensions.isEmpty, "a file never hands an extension the shell's tokens")
        #expect(here.searchSources == ["files"])
        #expect(!here.indexesFileNames)
        #expect(!here.fetchesExchangeRates)
        #expect(!here.syncsWithICloud)
        #expect(!here.shell.runs, "a file never switches on running commands")
        #expect(here.shell.prefix == .dollar, "the rest of the shell settings are the file's")
        #expect(here.aiOnThisMacOnly, "a file never loosens the promise")
        #expect(here.aliases == ["sample/planets": "p"], "everything else is the file's")
    }

    @Test func aFileWithoutShellSettingsDoesNotSwitchOnRunningCommands() throws {
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        here.shell.runs = false
        var file = try #require(JSONSerialization.jsonObject(with: AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false).exportedJSON()) as? [String: Any])
        file["shell"] = nil

        try here.importJSON(JSONSerialization.data(withJSONObject: file))

        #expect(!here.shell.runs)
    }

    @Test func aFileMayStillTightenThePromiseToKeepAIHere() throws {
        let file = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        file.aiOnThisMacOnly = true
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        try here.importJSON(file.exportedJSON())
        #expect(here.aiOnThisMacOnly)
    }

    @Test func anEditWaitingHereReachesTheOtherProcessWhenTheImportChangesNothing() throws {
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        here.save()
        let file = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        file.aliases = ["sample/planets": "p"]
        here.aliases = ["sample/planets": "p"]
        var saves = 0
        here.onSaved = { saves += 1 }

        try here.importJSON(file.exportedJSON())

        #expect(saves == 1, "the edit was saved while reading this Mac's settings, so that save tells the other process")
    }

    @Test func anImportNeverSwitchesOnWhatThisMacSwitchedOff() throws {
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        here.clipboardHistoryEnabled = false
        here.includeRaycastExtensions = false
        here.keepsReceipts = false
        here.remembersSearches = false
        here.diagnosticLogging = false
        here.syncsExtensionSettings = false
        here.disabledExtensions = ["evil"]
        here.disabledCommands = ["x/run"]
        here.enabledCommands = []
        here.menuBarCommands = []
        let file = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        file.clipboardHistoryEnabled = true
        file.includeRaycastExtensions = true
        file.keepsReceipts = true
        file.remembersSearches = true
        file.diagnosticLogging = true
        file.syncsExtensionSettings = true
        file.disabledExtensions = []
        file.disabledCommands = []
        file.enabledCommands = ["x/opt-in"]
        file.menuBarCommands = ["x/menu"]
        file.recordsExtensionAccess = false

        try here.importJSON(file.exportedJSON())

        #expect(!here.clipboardHistoryEnabled)
        #expect(!here.includeRaycastExtensions)
        #expect(!here.keepsReceipts)
        #expect(!here.remembersSearches)
        #expect(!here.diagnosticLogging)
        #expect(!here.syncsExtensionSettings)
        #expect(here.disabledExtensions == ["evil"])
        #expect(here.disabledCommands == ["x/run"])
        #expect(here.enabledCommands.isEmpty)
        #expect(here.menuBarCommands.isEmpty)
        #expect(here.recordsExtensionAccess, "a file never hides what extensions reach")
    }

    @Test func anImportMaySwitchOff() throws {
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        here.diagnosticLogging = true
        here.enabledCommands = ["a", "b"]
        here.menuBarCommands = ["a", "b"]
        here.disabledExtensions = []
        let file = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        file.clipboardHistoryEnabled = false
        file.includeRaycastExtensions = false
        file.keepsReceipts = false
        file.remembersSearches = false
        file.diagnosticLogging = false
        file.syncsExtensionSettings = false
        file.recordsExtensionAccess = false
        file.enabledCommands = ["a"]
        file.menuBarCommands = ["a"]
        file.disabledExtensions = ["c"]

        try here.importJSON(file.exportedJSON())

        #expect(!here.clipboardHistoryEnabled)
        #expect(!here.includeRaycastExtensions)
        #expect(!here.keepsReceipts)
        #expect(!here.remembersSearches)
        #expect(!here.diagnosticLogging)
        #expect(!here.syncsExtensionSettings)
        #expect(here.recordsExtensionAccess)
        #expect(here.enabledCommands == ["a"])
        #expect(here.menuBarCommands == ["a"])
        #expect(here.disabledExtensions == ["c"])
    }

    /// Fails when a setting kept on this Mac gets a rule that keepingConsent cannot apply to its kind of value.
    @Test func everySettingKeptOnThisMacHasAnImportRule() throws {
        let fresh = try #require(JSONSerialization.jsonObject(with: AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false).exportedJSON()) as? [String: Any])
        for (key, local) in SettingsSync.thisMacOnly where local.onImport != .takesFile {
            let isList = fresh[key] is [Any]
            guard fresh[key] is Bool || isList else {
                #expect(local.onImport == .keepsThisMac, "\(key) is neither a switch nor a list, so an import cannot merge it")
                continue
            }
            let on: Any = isList ? ["probe"] : true
            let off: Any = isList ? [String]() : false
            let addsOnly = local.onImport == .mayOnlyAdd
            var mine = fresh
            mine[key] = addsOnly ? on : off
            let defaults = MemoryDefaults()
            try defaults.set(JSONSerialization.data(withJSONObject: mine), forKey: "settings")
            let here = AppSettings(defaults: defaults, savesAfterEdits: false)
            let hereJSON = try #require(JSONSerialization.jsonObject(with: here.exportedJSON()) as? [String: Any])
            var theirs = fresh
            theirs[key] = addsOnly ? off : on

            let kept = try SettingsTransfer.keepingConsent(JSONSerialization.data(withJSONObject: theirs), of: here)

            let result = try #require(JSONSerialization.jsonObject(with: kept) as? [String: Any])
            #expect(SettingsSync.text(result[key] as Any) == SettingsSync.text(hereJSON[key] as Any), "\(key) took the file's value")
        }
    }
}
