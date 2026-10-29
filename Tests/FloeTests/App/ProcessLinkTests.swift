//
//  ProcessLinkTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
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
    private let key = SymmetricKey(size: .bits256)

    private func gate(own: Int32, peer: Int32?, key: SymmetricKey?) -> LinkGate {
        LinkGate(ownPid: own, key: { key }, peerPid: { peer })
    }

    @Test func onlyThePeerSigningWithTheKeyIsAccepted() throws {
        let peer = gate(own: 200, peer: 100, key: key)
        let mine = gate(own: 100, peer: 200, key: key)
        let signature = try #require(peer.signature(of: .removeSyncedSettings, sequence: 1))
        #expect(mine.accepts(.removeSyncedSettings, sender: 200, sequence: 1, signature: signature))
        #expect(!mine.accepts(.removeSyncedSettings, sender: 200, sequence: 1, signature: nil), "the peer's pid alone proves nothing")
        #expect(!mine.accepts(.removeSyncedSettings, sender: 200, sequence: 2, signature: signature), "the number is signed with the message")
        #expect(!mine.accepts(.quit, sender: 200, sequence: 1, signature: signature), "so is the kind")
        #expect(!mine.accepts(.removeSyncedSettings, sender: 300, sequence: 1, signature: signature), "an unknown sender is ignored")
        let stranger = gate(own: 200, peer: 100, key: SymmetricKey(size: .bits256))
        let forged = try #require(stranger.signature(of: .removeSyncedSettings, sequence: 1))
        #expect(!mine.accepts(.removeSyncedSettings, sender: 200, sequence: 1, signature: forged), "another key's signature is refused")
    }

    @Test func nothingIsAcceptedOrSignedWithoutAPeerOrAKey() throws {
        let signature = try #require(gate(own: 200, peer: 100, key: key).signature(of: .quit, sequence: 1))
        #expect(!gate(own: 100, peer: nil, key: key).accepts(.quit, sender: 200, sequence: 1, signature: signature))
        #expect(!gate(own: 100, peer: 200, key: nil).accepts(.quit, sender: 200, sequence: 1, signature: signature))
        #expect(gate(own: 100, peer: 200, key: nil).signature(of: .quit, sequence: 1) == nil)
    }

    @Test func aSenderClaimingToBeThisProcessIsRejectedEvenIfItIsThePeer() throws {
        let itself = gate(own: 100, peer: 100, key: key)
        let signature = try #require(itself.signature(of: .quit, sequence: 1))
        #expect(!itself.accepts(.quit, sender: 100, sequence: 1, signature: signature))
    }

    @Test func theKeyTravelsAsOneLineAndComesBackWhole() throws {
        let decoded = try #require(LinkKey.decoded(LinkKey.encoded(key)))
        #expect(decoded == key)
        #expect(LinkKey.decoded(Data("short\n".utf8)) == nil)
    }

    @Test func theKeyIsReadFromAPipeAndAPipeLeftEmptyDoesNotHang() throws {
        let written = Pipe()
        written.fileHandleForWriting.write(LinkKey.encoded(key))
        #expect(LinkKey.fromStandardInput(written.fileHandleForReading.fileDescriptor, waiting: 1000) == key)

        // Held open and never written to: a wrapper's pipe, which must not keep Settings from starting.
        let held = Pipe()
        let started = Date()
        #expect(LinkKey.fromStandardInput(held.fileHandleForReading.fileDescriptor, waiting: 50) == nil)
        #expect(Date().timeIntervalSince(started) < 5)
        _ = held.fileHandleForWriting
    }
}

struct LinkMessageTests {
    @Test func everyKindHasItsOwnNotificationName() {
        let names = Set(LinkMessage.Kind.allCases.map(\.name))
        #expect(names.count == LinkMessage.Kind.allCases.count)
        #expect(names.allSatisfy { $0.rawValue.hasPrefix("org.thaw.floe.link.") })
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
    private let key = SymmetricKey(size: .bits256)

    private func gate(own: Int32, peer: @escaping () -> Int32?) -> LinkGate {
        LinkGate(ownPid: own, key: { [key] in key }, peerPid: peer)
    }

    /// What the settings process with this pid would post, signed with the pair's key.
    private func info(_ message: LinkMessage, pid: Int32, sequence: UInt64 = 1) -> [String: String] {
        let signature = gate(own: pid) { 7 }.signature(of: message, sequence: sequence) ?? ""
        return ["pid": String(pid), "payload": message.payload, "sequence": String(sequence), "signature": signature]
    }

    @Test func aMessageCarriesTheSendersPidNumberAndSignature() throws {
        let outbox = Outbox()
        let link = ProcessLink(role: .settings, gate: gate(own: 7) { 1 }, transport: outbox.transport)
        link.send(.recording(true))
        link.send(.settingsChanged)
        #expect(outbox.posted.map(\.name) == [LinkMessage.Kind.recording.name, LinkMessage.Kind.settingsChanged.name])
        let first = try #require(outbox.posted.first?.info)
        #expect(first["pid"] == "7")
        #expect(first["payload"] == "1")
        #expect(first["sequence"] == "1")
        #expect(first["signature"] == gate(own: 7) { 1 }.signature(of: .recording(true), sequence: 1))
        #expect(outbox.posted.last?.info["sequence"] == "2")
    }

    @Test func nothingIsPostedWhileNoSettingsProcessRunsOrWithoutAKey() {
        let outbox = Outbox()
        ProcessLink(role: .launcher, gate: gate(own: 7) { nil }, transport: outbox.transport).send(.settingsChanged)
        ProcessLink(role: .settings, gate: LinkGate(ownPid: 7, key: { nil }, peerPid: { 1 }), transport: outbox.transport).send(.settingsChanged)
        #expect(outbox.posted.isEmpty)
    }

    @Test func aLinkListensOnlyForWhatItsRoleTakes() {
        let outbox = Outbox()
        let link = ProcessLink(role: .settings, gate: gate(own: 7) { 1 }, transport: outbox.transport)
        link.start()
        #expect(Set(outbox.observed) == Set([LinkMessage.Kind.settingsChanged, .storeChanged, .showPage, .updatesState, .thawStatus, .fileIndexState, .syncState].map(\.name)))
    }

    @Test func theLauncherActsOnItsSettingsProcessOnly() {
        var child: Int32? = 50
        var received: [LinkMessage] = []
        let link = ProcessLink(role: .launcher, gate: gate(own: 7) { child }, transport: Outbox().transport)
        link.handler = { received.append($0) }

        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: info(.settingsChanged, pid: 50))
        #expect(received == [.settingsChanged])

        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: info(.settingsChanged, pid: 7, sequence: 2))
        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: info(.settingsChanged, pid: 51, sequence: 2))
        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: [:])
        link.receive(name: LinkMessage.Kind.settingsChanged.name, info: ["pid": "fifty", "payload": "", "sequence": "2"])
        #expect(received == [.settingsChanged], "its own, a stranger's, an unsigned and a garbled message all do nothing")

        child = nil
        link.receive(name: LinkMessage.Kind.quit.name, info: info(.quit, pid: 50, sequence: 3))
        #expect(received == [.settingsChanged], "a settings process that has ended is no longer listened to")
    }

    @Test func aMessageCopiedFromTheSessionCannotBeSentAgain() {
        var received: [LinkMessage] = []
        let link = ProcessLink(role: .launcher, gate: gate(own: 7) { 50 }, transport: Outbox().transport)
        link.handler = { received.append($0) }
        let removal = info(.removeSyncedSettings, pid: 50, sequence: 4)
        link.receive(name: LinkMessage.Kind.removeSyncedSettings.name, info: removal)
        link.receive(name: LinkMessage.Kind.removeSyncedSettings.name, info: removal)
        link.receive(name: LinkMessage.Kind.removeSyncedSettings.name, info: info(.removeSyncedSettings, pid: 50, sequence: 3))
        #expect(received == [.removeSyncedSettings], "a repeat, or an earlier number, is refused")
        link.receive(name: LinkMessage.Kind.quit.name, info: info(.quit, pid: 50, sequence: 5))
        #expect(received == [.removeSyncedSettings, .quit])
    }

    @Test func aNewSettingsProcessWithAnOldPidCountsFromOneAgain() {
        var key = SymmetricKey(size: .bits256)
        var received: [LinkMessage] = []
        let link = ProcessLink(role: .launcher, gate: LinkGate(ownPid: 7, key: { key }, peerPid: { 50 }), transport: Outbox().transport)
        link.handler = { received.append($0) }
        func signed(_ message: LinkMessage, sequence: UInt64) -> [String: String] {
            let signature = LinkGate(ownPid: 50, key: { key }, peerPid: { 7 }).signature(of: message, sequence: sequence) ?? ""
            return ["pid": "50", "payload": message.payload, "sequence": String(sequence), "signature": signature]
        }
        link.receive(name: LinkMessage.Kind.ready.name, info: signed(.ready, sequence: 9))
        key = SymmetricKey(size: .bits256)
        link.receive(name: LinkMessage.Kind.ready.name, info: signed(.ready, sequence: 1))
        #expect(received == [.ready, .ready])
    }

    @Test func aMessageForTheOtherSideOrWithABadPayloadIsDropped() {
        var received: [LinkMessage] = []
        let link = ProcessLink(role: .launcher, gate: gate(own: 7) { 50 }, transport: Outbox().transport)
        link.handler = { received.append($0) }
        link.receive(name: LinkMessage.Kind.showPage.name, info: info(LinkMessage(.showPage, "about"), pid: 50, sequence: 1))
        link.receive(name: LinkMessage.Kind.rescan.name, info: info(LinkMessage(.rescan, "everything"), pid: 50, sequence: 2))
        link.receive(name: Notification.Name("org.thaw.floe.link.format-disk"), info: info(.quit, pid: 50, sequence: 3))
        #expect(received.isEmpty)
        link.receive(name: LinkMessage.Kind.rescan.name, info: info(.rescan(.scripts), pid: 50, sequence: 4))
        #expect(received == [.rescan(.scripts)])
    }
}
