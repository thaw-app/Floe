//
//  PanelLifetime.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

nonisolated enum PanelRequest: Codable, Equatable, Sendable {
    case show, toggle, hide, onboarding
    case command(String, arguments: Data?)
    case script(String)
    case builtIn(String)
    case hud(String)
    case url(URL)
}

nonisolated enum PanelPacket: Codable, Sendable {
    case ready
    case present(PanelRequest)
    case request(PanelRequest, sequence: Int)
    case idle(sequence: Int)
    case shutdown
    case reload, refresh
    case appearance(String)
    case settings(String, String)
    case openSettings(String?)
    case quit
    case used(String)
    case query(String)
    case receipt(Receipt)
    case receiptUndone(UUID, Date)
    case timers([RunningTimer])
    case startTimer(TimerDraft)
    case stopTimer(UUID)
    case clipboardChanged, clearClipboard
    case deleteClipboard(UUID)
    case pinClipboard(UUID)
}

/// Serializes opening and closing: an idle report from before the latest request cannot close
/// a reopened panel, and requests arriving during shutdown wait for a fresh process.
struct PanelLifetime {
    enum Effect: Equatable {
        case start
        case send(Message)
    }

    enum Message: Equatable {
        case request(PanelRequest, sequence: Int)
        case shutdown

        var packet: PanelPacket {
            switch self {
            case let .request(request, sequence): .request(request, sequence: sequence)
            case .shutdown: .shutdown
            }
        }
    }

    private enum Phase { case stopped, starting, ready, closing }
    private var phase = Phase.stopped
    private var pending: [PanelRequest] = []
    private var sequence = 0

    mutating func request(_ request: PanelRequest) -> [Effect] {
        if phase == .stopped, request == .hide {
            return []
        }
        if phase == .ready {
            return [deliver(request)]
        }
        pending.append(request)
        guard phase == .stopped else { return [] }
        phase = .starting
        return [.start]
    }

    mutating func ready() -> [Effect] {
        guard phase == .starting else { return [] }
        phase = .ready
        let requests = pending
        pending.removeAll()
        return requests.map { deliver($0) }
    }

    mutating func idle(sequence: Int) -> [Effect] {
        guard phase == .ready, sequence == self.sequence else { return [] }
        phase = .closing
        return [.send(.shutdown)]
    }

    mutating func exited() -> [Effect] {
        phase = pending.isEmpty ? .stopped : .starting
        return pending.isEmpty ? [] : [.start]
    }

    private mutating func deliver(_ request: PanelRequest) -> Effect {
        sequence += 1
        return .send(.request(request, sequence: sequence))
    }
}
