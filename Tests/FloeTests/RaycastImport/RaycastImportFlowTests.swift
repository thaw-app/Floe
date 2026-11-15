//
//  RaycastImportFlowTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
final class RaycastImportFlowTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-tests-\(UUID().uuidString)")
    private lazy var store = QuicklinkStore(file: folder.appendingPathComponent("quicklinks.json"))
    private var asked: [Bool] = []
    private var told: [(title: String, detail: String)] = []

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// readings answers each read in turn, and passphrases each time the flow asks for one.
    private func environment(file: URL? = URL(fileURLWithPath: "/tmp/export.json"), readings: [RaycastExport.Reading], passphrases: [String?] = []) -> RaycastImportFlow.Environment {
        var readings = readings
        var passphrases = passphrases
        return RaycastImportFlow.Environment(
            chooseFile: { file },
            askPassphrase: { [unowned self] again in
                asked.append(again)
                return passphrases.isEmpty ? nil : passphrases.removeFirst()
            },
            read: { _, _ in readings.removeFirst() },
            apps: QuicklinkImport.Apps(home: URL(fileURLWithPath: "/Users/me"), app: { _ in nil }),
            tell: { [unowned self] in told.append(($0, $1)) }
        )
    }

    @Test func anExportsLinksAreAddedAndTheSummarySaysWhatWasLeftOut() async {
        let before = store.links.count
        await RaycastImportFlow.run(into: store, environment: environment(readings: [.quicklinks([
            RaycastQuicklink(name: "Docs", link: "https://docs.example/?q={argument}"),
            RaycastQuicklink(name: "Repo", link: "https://github.com", openWith: "Arc"),
            RaycastQuicklink(name: "Today", link: "https://d.example/{date}"),
            RaycastQuicklink(name: "Google", link: "https://www.google.com/search?q={argument}"),
        ])]))
        #expect(store.links.count == before + 2)
        #expect(store.links.suffix(2).map(\.name) == ["Docs", "Repo"])
        #expect(told.map(\.title) == ["Imported 2 quicklinks"])
        #expect(told.first?.detail == """
        Repo opens in your default app: its app isn't on this Mac.
        Not imported:
        Today: Floe can't fill {date}.
        Google: already in Floe.
        """)
        #expect(asked.isEmpty)
    }

    @Test func aBackupAsksForItsPassphraseUntilItIsRight() async {
        await RaycastImportFlow.run(into: store, environment: environment(
            readings: [.needsPassphrase, .wrongPassphrase, .quicklinks([RaycastQuicklink(name: "Docs", link: "https://docs.example")])],
            passphrases: ["wrong", "right"]
        ))
        #expect(asked == [false, true])
        #expect(told.map(\.title) == ["Imported 1 quicklink"])
        #expect(told.first?.detail == "")
    }

    @Test func cancellingThePassphraseOrTheFileChangesNothing() async {
        let before = store.links
        await RaycastImportFlow.run(into: store, environment: environment(readings: [.needsPassphrase]))
        await RaycastImportFlow.run(into: store, environment: environment(file: nil, readings: []))
        #expect(store.links == before)
        #expect(told.isEmpty)
        #expect(asked == [false])
    }

    @Test func leavingThePageWhileTheFileIsReadStopsTheImport() async {
        let before = store.links
        var environment = environment(readings: [])
        environment.read = { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .quicklinks([RaycastQuicklink(name: "Docs", link: "https://docs.example")])
        }
        await RaycastImportFlow.run(into: store, environment: environment)
        #expect(store.links == before)
        #expect(told.isEmpty)
    }

    @Test func aFileThatIsNotAnExportIsSaidToBeOne() async {
        await RaycastImportFlow.run(into: store, environment: environment(readings: [.notAnExport]))
        #expect(told.map(\.title) == ["This isn't a Raycast export"])
    }

    @Test func anExportWithNothingNewSaysSo() async {
        await RaycastImportFlow.run(into: store, environment: environment(readings: [.quicklinks([
            RaycastQuicklink(name: "Google", link: "https://www.google.com/search?q={argument}"),
        ])]))
        #expect(told.map(\.title) == ["No quicklinks imported"])
        #expect(told.first?.detail == "Not imported:\nGoogle: already in Floe.")
    }
}
