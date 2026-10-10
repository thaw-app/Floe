//
//  ToastWithoutFooterTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// A toast is drawn in the footer of a command's view. Where there is none, the model says it with the HUD.
@MainActor
struct ToastWithoutFooterTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-toast-tests-\(UUID().uuidString)")
    private let model: LauncherModel
    private let said = Said()

    private final class Said {
        var lines: [String] = []
    }

    init() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "floe-toast-tests-\(UUID().uuidString)")!)
        model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("checkpoints.json"))
        model.showHUD = { [said] in said.lines.append($0) }
    }

    private func session(mode: String) -> ExtensionSession {
        let command = ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/floe-toast-tests"), extensionName: "floe-toast-tests",
            extensionTitle: "Tests", source: .local, name: "connect", title: "Connect",
            mode: mode, interval: nil, icon: nil, arguments: [], extensionPreferences: [], commandPreferences: []
        )
        let session = ExtensionSession(command: command)
        session.onMessage = { [model, weak session] message in
            if let session {
                model.handle(message, from: session)
            }
        }
        return session
    }

    /// Applies a message the way the host's output is applied, through the production parser.
    private func send(_ json: [String: Any], to session: ExtensionSession) throws {
        let message = try #require(DecodedHostMessage.decode(JSONSerialization.data(withJSONObject: json)))
        session.apply(message)
    }

    @Test func aCommandWithoutAViewSaysItsProgressAndItsSuccess() throws {
        let connect = session(mode: "no-view")
        try send(["type": "toast", "id": 1, "style": "animated", "title": "Connecting to NetBird", "message": "Please wait..."], to: connect)
        try send(["type": "toast", "id": 1, "hidden": true], to: connect)
        try send(["type": "close"], to: connect)
        try send(["type": "toast", "id": 2, "style": "success", "title": "Connected to NetBird", "message": ""], to: connect)
        try send(["type": "exit"], to: connect)
        #expect(said.lines == ["Connecting to NetBird: Please wait...", "Connected to NetBird"])
    }

    @Test func aCommandWithoutAViewSaysWhyItFailed() throws {
        let connect = session(mode: "no-view")
        try send(["type": "toast", "id": 1, "style": "failure", "title": "Failed to connect", "message": "NetBird daemon is not running.", "primaryTitle": "Copy Logs"], to: connect)
        try send(["type": "exit"], to: connect)
        #expect(said.lines == ["Failed to connect: NetBird daemon is not running."])
    }

    @Test func aRejectionNobodyHandledIsSaidToo() throws {
        let connect = session(mode: "no-view")
        try send(["type": "error", "message": "spawn netbird ENOENT", "fatal": false], to: connect)
        #expect(said.lines == ["Extension error: spawn netbird ENOENT"])
    }

    @Test func aToastSentAgainUnchangedIsSaidOnceAndEachRunSaysItsOwn() throws {
        let update = session(mode: "no-view")
        let toast: [String: Any] = ["type": "toast", "id": 1, "style": "animated", "title": "Updating NetBird", "message": "Checking current version..."]
        try send(toast, to: update)
        try send(toast, to: update)
        try send(toast.merging(["message": "Updating via Homebrew..."]) { $1 }, to: update)
        #expect(said.lines == ["Updating NetBird: Checking current version...", "Updating NetBird: Updating via Homebrew..."])
        try send(toast.merging(["message": "Updating via Homebrew..."]) { $1 }, to: session(mode: "no-view"))
        #expect(said.lines.count == 3, "another run of the command starts its toasts at the same id")
    }

    @Test func aToastWithNothingToSayShowsNothing() throws {
        try send(["type": "toast", "id": 1], to: session(mode: "no-view"))
        #expect(said.lines.isEmpty)
    }

    @Test func aViewOnScreenKeepsItsToastsInItsFooter() throws {
        let view = session(mode: "view")
        model.panelWillShow()
        try send(["type": "toast", "id": 1, "style": "success", "title": "Saved"], to: view)
        #expect(view.toast?.title == "Saved")
        #expect(said.lines.isEmpty)
    }

    @Test func aViewThatClosedTheWindowSaysWhatItFinishedAndNotItsProgress() throws {
        let view = session(mode: "view")
        model.panelWillShow()
        model.panelDidHide()
        try send(["type": "toast", "id": 1, "style": "animated", "title": "Refreshing"], to: view)
        try send(["type": "toast", "id": 2, "style": "success", "title": "Copied the link"], to: view)
        #expect(said.lines == ["Copied the link"])
    }
}
