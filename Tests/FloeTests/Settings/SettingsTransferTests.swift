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
        #expect(here.searchSources == ["files"])
        #expect(!here.indexesFileNames)
        #expect(!here.fetchesExchangeRates)
        #expect(!here.syncsWithICloud)
        #expect(!here.shell.runs, "a file never switches on running commands")
        #expect(here.shell.prefix == .dollar, "the rest of the shell settings are the file's")
        #expect(here.aiOnThisMacOnly, "a file never loosens the promise")
        #expect(here.aliases == ["sample/planets": "p"], "everything else is the file's")
    }

    @Test func aFileMayStillTightenThePromiseToKeepAIHere() throws {
        let file = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        file.aiOnThisMacOnly = true
        let here = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        try here.importJSON(file.exportedJSON())
        #expect(here.aiOnThisMacOnly)
    }
}
