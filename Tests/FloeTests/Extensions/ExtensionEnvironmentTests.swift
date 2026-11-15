//
//  ExtensionEnvironmentTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ExtensionEnvironmentTests {
    private let shell = [
        "PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/ada", "LANG": "en_US.UTF-8", "LC_CTYPE": "UTF-8",
        "SSH_AUTH_SOCK": "/private/tmp/agent", "HOMEBREW_PREFIX": "/opt/homebrew",
        "GITHUB_TOKEN": "ghp_secret", "OPENAI_API_KEY": "sk-secret", "HOMEBREW_GITHUB_API_TOKEN": "ghp_brew", "AWS_SECRET_ACCESS_KEY": "aws",
    ]

    @Test func namesAndPrefixesOnTheListPassAndTokensDoNot() {
        #expect(ExtensionEnvironment.handedOn(shell, passesShellEnvironment: false) == [
            "PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/ada", "LANG": "en_US.UTF-8", "LC_CTYPE": "UTF-8",
            "SSH_AUTH_SOCK": "/private/tmp/agent", "HOMEBREW_PREFIX": "/opt/homebrew",
        ])
        #expect(!ExtensionEnvironment.isAllowed("HOMEBREW_GITHUB_API_TOKEN"), "Homebrew's names are exact, so its token stays out")
        #expect(!ExtensionEnvironment.isAllowed("AWS_SECRET_ACCESS_KEY"))
        #expect(!ExtensionEnvironment.isAllowed("lc_ctype"), "a prefix matches its own case only")
    }

    @Test func theSwitchHandsOnEverything() {
        #expect(ExtensionEnvironment.handedOn(shell, passesShellEnvironment: true) == shell)
    }

    @Test func eachEntryOnTheListSaysWhy() {
        for allowance in ExtensionEnvironment.allowances {
            #expect(!allowance.reason.isEmpty)
            #expect(!allowance.names.isEmpty || !allowance.prefixes.isEmpty)
        }
    }

    @Test func theHostIsHandedTheListAndFloesOwnVariables() {
        let variables = ExtensionSession.hostVariables(shell, grants: [.ai])
        #expect(variables["GITHUB_TOKEN"] == nil)
        #expect(variables["OPENAI_API_KEY"] == nil)
        #expect(variables["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(variables["FLOE_SECRETS"] == "input", "Floe's own variables are not limited by the list")
        #expect(variables["FLOE_AI"] == "1")
        #expect(variables["NODE_ENV"] == "production")

        let whole = ExtensionSession.hostVariables(shell, passesShellEnvironment: true, grants: [])
        #expect(whole["GITHUB_TOKEN"] == "ghp_secret", "the switch restores what the shell exports")
        #expect(whole["FLOE_LAUNCH_TYPE"] == "userInitiated")
    }

    @MainActor @Test func whoGetsTheShellEnvironmentIsKeptInSettings() {
        let defaults = MemoryDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.shellEnvironmentExtensions.isEmpty, "no extension gets it until the user says so")
        settings.shellEnvironmentExtensions.insert("agent-usage")
        settings.save()
        #expect(AppSettings(defaults: defaults).shellEnvironmentExtensions == ["agent-usage"])
        #expect(SettingsSync.thisMacOnly["shellEnvironmentExtensions"] != nil, "a shell environment belongs to one Mac")
    }
}
