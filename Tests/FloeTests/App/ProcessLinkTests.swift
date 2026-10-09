//
//  ProcessLinkTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// What a link posted, kept instead of being sent to the session's notification center.
private final class Outbox {
    var posted: [(name: Notification.Name, info: [String: String])] = []
    var observed: [Notification.Name] = []

    var transport: ProcessLink.Transport {
        ProcessLink.Transport(
            post: { [self] name, info in posted.append((name, info)) },
            observe: { [self] _, name in observed.append(name) }
        )
    }
}

struct LinkGateTests {
    @Test func onlyThePeerIsAccepted() {
        let gate = LinkGate(ownPid: 100) { 200 }
        #expect(gate.accepts(sender: 200))
        #expect(!gate.accepts(sender: 100), "a process ignores what it sent itself")
        #expect(!gate.accepts(sender: 300), "an unknown sender is ignored")
        #expect(!gate.accepts(sender: nil), "a message that names no sender is ignored")
    }

    @Test func nothingIsAcceptedWithoutAPeer() {
        let gate = LinkGate(ownPid: 100) { nil }
        #expect(!gate.accepts(sender: 200))
        #expect(!gate.accepts(sender: 100))
    }

    @Test func aSenderClaimingToBeThisProcessIsRejectedEvenIfItIsThePeer() {
        let gate = LinkGate(ownPid: 100) { 100 }
        #expect(!gate.accepts(sender: 100))
    }
}

struct LinkMessageTests {
    @Test func everyKindHasItsOwnNotificationName() {
        let names = Set(LinkMessage.Kind.allCases.map(\.name))
        #expect(names.count == LinkMessage.Kind.allCases.count)
        #expect(names.allSatisfy { $0.rawValue.hasPrefix("com.thaw.floe.link.") })
    }

    @Test func eachSideTakesOnlyWhatTheOtherSends() {
        #expect(LinkMessage.Kind.settingsChanged.isMeant(for: .launcher))
        #expect(LinkMessage.Kind.settingsChanged.isMeant(for: .settings))
        #expect(LinkMessage.Kind.showPage.isMeant(for: .settings))
        #expect(!LinkMessage.Kind.showPage.isMeant(for: .launcher))
        for kind in [LinkMessage.Kind.ready, .pageChanged, .recording, .updates, .rescan, .clearClipboardHistory, .forwardURL, .removeSyncedSettings, .quit] {
            #expect(kind.isMeant(for: .launcher))
            #expect(!kind.isMeant(for: .settings), "\(kind) is something the settings process says, not hears")
        }
    }

    @Test func payloadsAreChecked() {
        #expect(LinkMessage.storeChanged(.snippets).isWellFormed)
        #expect(!LinkMessage(.storeChanged, "passwords").isWellFormed)
        #expect(LinkMessage.rescan(.commands).scan == .commands)
        #expect(!LinkMessage(.rescan, "everything").isWellFormed)
        #expect(LinkMessage.recording(true).isRecording)
        #expect(!LinkMessage.recording(false).isRecording)
        #expect(!LinkMessage(.recording, "yes").isWellFormed)
        #expect(!LinkMessage(.quit, "now").isWellFormed)
        #expect(LinkMessage(.syncState, SyncStatus(state: .full, skipped: 2).text).isWellFormed)
        #expect(!LinkMessage(.syncState, "soon").isWellFormed)
        #expect(!LinkMessage(.removeSyncedSettings, "all").isWellFormed)
        #expect(LinkMessage(.showPage, "").isWellFormed, "no page means only come forward")
    }
}

struct ProcessLinkTests {
    private func info(pid: Int32, payload: String = "") -> [String: String] {
        ["pid": String(pid), "payload": payload]
    }

    @Test func aMessageCarriesTheSendersPid() {
        let outbox = Outbox()
        let link = ProcessLink(role: .settings, gate: LinkGate(ownPid: 7) { 1 }, transport: outbox.transport)
        link.send(.recording(true))
        #expect(outbox.posted.count == 1)
        #expect(outbox.posted.first?.name == LinkMessage.Kind.recording.name)
        #expect(outbox.posted.first?.info == ["pid": "7", "payload": "1"])
    }

    @Test func nothingIsPostedWhileNoSettingsProcessRuns() {
        let outbox = Outbox()
        let link = ProcessLink(role: .launcher, gate: LinkGate(ownPid: 7) { nil }, transport: outbox.transport)
        link.send(.settingsChanged)
        #expect(outbox.posted.isEmpty)
    }

    @Test func aLinkListensOnlyForWhatItsRoleTakes() {
        let outbox = Outbox()
        let link = ProcessLink(role: .settings, gate: LinkGate(ownPid: 7) { 1 }, transport: outbox.transport)
        link.start()
        #expect(Set(outbox.observed) == Set([LinkMessage.Kind.settingsChanged, .storeChanged, .showPage, .updatesState, .thawStatus, .fileIndexState, .syncState].map(\.name)))
    }

    @Test func theLauncherActsOnItsSettingsProcessOnly() {
        var child: Int32? = 50
        var received: [LinkMessage] = []
        let link = ProcessLink(role: .launcher, gate: LinkGate(ownPid: 7) { child }, transport: Outbox().transport)
        link.handler = { received.append($0) }

        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: info(pid: 50))
        #expect(received == [.settingsChanged])

        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: info(pid: 7))
        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: info(pid: 51))
        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: [:])
        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: ["pid": "fifty", "payload": ""])
        #expect(received == [.settingsChanged], "its own, a stranger's, an unsigned and a garbled message all do nothing")

        child = nil
        link.receive(name: LinkMessage.Kind.quit.name, info: info(pid: 50))
        #expect(received == [.settingsChanged], "a settings process that has ended is no longer listened to")
    }

    @Test func aMessageForTheOtherSideOrWithABadPayloadIsDropped() {
        var received: [LinkMessage] = []
        let link = ProcessLink(role: .launcher, gate: LinkGate(ownPid: 7) { 50 }, transport: Outbox().transport)
        link.handler = { received.append($0) }
        link.receive(name: LinkMessage.Kind.showPage.name, info: info(pid: 50, payload: "about"))
        link.receive(name: LinkMessage.Kind.rescan.name, info: info(pid: 50, payload: "everything"))
        link.receive(name: Notification.Name("com.thaw.floe.link.format-disk"), info: info(pid: 50))
        #expect(received.isEmpty)
        link.receive(name: LinkMessage.Kind.rescan.name, info: info(pid: 50, payload: "scripts"))
        #expect(received == [.rescan(.scripts)])
    }
}
