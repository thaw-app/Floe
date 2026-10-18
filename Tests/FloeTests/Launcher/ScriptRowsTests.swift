//
//  ScriptRowsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// Script commands as a row owner, with a runner that answers at once: no script is run.
@MainActor
struct ScriptRowsTests {
    private final class Asked {
        var left = 0
        var used: [String] = []
        var huds: [String] = []
        var windows: [String] = []
        var confirmed = 0
    }

    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "no"
        }
    }

    private let asked = Asked()

    private func script(_ mode: ScriptMode, confirming: Bool = false) -> ScriptCommand {
        ScriptCommand(
            file: URL(fileURLWithPath: "/tmp/deploy.sh"), title: "Deploy", packageName: nil, mode: mode,
            needsConfirmation: confirming, icon: nil, arguments: []
        )
    }

    private func rows(status: Int32 = 0, stdout: String = "", stderr: String = "") -> ScriptRows {
        answering(status: status, stdout: stdout, stderr: stderr, on: ScriptRows())
    }

    /// Makes the rows' runner answer as a script that printed this and ended with this status.
    @discardableResult
    private func answering(status: Int32 = 0, stdout: String = "", stderr: String = "", on rows: ScriptRows) -> ScriptRows {
        let asked = asked
        rows.host = RowHost(showHUD: { asked.huds.append($0) }, leave: { asked.left += 1 })
        rows.recordUse = { asked.used.append($0) }
        rows.showOutput = { title, output in asked.windows.append("\(title): \(output)") }
        rows.confirms = { _ in
            asked.confirmed += 1
            return false
        }
        rows.runScript = { _, arguments in
            ShellResult(status: status, stdout: Data((stdout + arguments.joined(separator: ",")).utf8), stderr: Data(stderr.utf8))
        }
        return rows
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0 ..< 200 where !done() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aScriptIsOpenedWithTheArgumentsTypedAfterItsTitle() async {
        let rows = rows(stdout: "args: ")
        rows.typed = { "Deploy staging \"two words\"" }
        let script = script(.fullOutput)
        #expect(rows.returnTitle(for: .script(script)) == nil)
        #expect(!rows.open(.emojiSearch, flags: []))
        #expect(rows.open(.script(script), flags: []))
        await settle { !asked.windows.isEmpty }
        #expect(asked.windows == ["Deploy: args: staging,two words"])
        #expect(asked.used == [RootItem.script(script).id])
        #expect(asked.left == 1)
    }

    @Test func aCompactScriptShowsItsLastLineOrDoneAndASilentOneNothing() async {
        let rows = rows(stdout: "one\ntwo\n")
        rows.run(script(.compact))
        await settle { asked.huds.count == 1 }
        answering(on: rows).run(script(.inline))
        await settle { asked.huds.count == 2 }
        #expect(asked.huds.first == "two")
        answering(stdout: "quiet", on: rows).run(script(.silent))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(asked.huds.count == 2)
        #expect(asked.windows.isEmpty)
    }

    @Test func aFailedScriptSaysWhyFromItsLastErrorLineOrItsExitCode() async {
        let rows = rows(status: 1, stdout: "fine", stderr: "first\nbroke\n")
        rows.run(script(.fullOutput))
        await settle { asked.huds.count == 1 }
        answering(status: 3, on: rows).run(script(.silent))
        await settle { asked.huds.count == 2 }
        #expect(asked.huds.first?.hasSuffix("broke") == true)
        #expect(asked.huds.last?.contains("3") == true)
        #expect(asked.windows.isEmpty)
    }

    @Test func aScriptThatCouldNotStartSaysWhy() async {
        let rows = rows()
        rows.runScript = { _, _ in throw Failure() }
        rows.run(script(.compact))
        await settle { !asked.huds.isEmpty }
        #expect(asked.huds.count == 1)
        #expect(asked.huds.first?.hasSuffix("no") == true)
    }

    @Test func aScriptThatAsksFirstRunsOnlyOnceConfirmed() async {
        let rows = rows(stdout: "done")
        rows.run(script(.compact, confirming: true))
        #expect(asked.confirmed == 1)
        #expect(asked.used.isEmpty)
        #expect(asked.left == 0)
        rows.confirms = { _ in true }
        rows.run(script(.compact, confirming: true))
        await settle { !asked.huds.isEmpty }
        #expect(asked.huds == ["done"])
    }
}
