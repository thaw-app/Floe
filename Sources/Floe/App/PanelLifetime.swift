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
        case start, terminate
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

    private enum Phase { case stopped, starting, timedOut, ready, closing }
    private var phase = Phase.stopped
    private var pending: [PanelRequest] = []
    private var sequence = 0
    private var failedStarts = 0

    var isAwaitingReadiness: Bool {
        phase == .starting
    }

    /// Queues work until readiness; a new user request after exhaustion gets a fresh retry budget.
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
        failedStarts = 0
        return [.start]
    }

    /// Delivers queued work once, ignoring readiness from a child already being terminated.
    mutating func ready() -> [Effect] {
        guard phase == .starting else { return [] }
        phase = .ready
        failedStarts = 0
        let requests = pending
        pending.removeAll()
        return requests.map { deliver($0) }
    }

    /// Closes only when the idle report acknowledges the most recently delivered request.
    mutating func idle(sequence: Int) -> [Effect] {
        guard phase == .ready, sequence == self.sequence else { return [] }
        phase = .closing
        return [.send(.shutdown)]
    }

    /// Retains pending work until exit, but prevents a late ready packet from consuming it.
    mutating func readinessTimedOut() -> [Effect] {
        guard phase == .starting else { return [] }
        phase = .timedOut
        return [.terminate]
    }

    /// Retries undelivered work, allowing at most three consecutive crashed or timed-out starts.
    mutating func exited() -> [Effect] {
        if phase == .starting || phase == .timedOut {
            failedStarts += 1
            if failedStarts >= 3 {
                pending.removeAll()
            }
        }
        phase = pending.isEmpty ? .stopped : .starting
        return pending.isEmpty ? [] : [.start]
    }

    /// Tags each delivery so an older idle notification cannot dismiss newer work.
    private mutating func deliver(_ request: PanelRequest) -> Effect {
        sequence += 1
        return .send(.request(request, sequence: sequence))
    }
}
