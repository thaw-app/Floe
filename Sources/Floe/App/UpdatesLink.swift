//
//  UpdatesLink.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Observation
import ThawUI

/// What the settings process asks of the launcher's updater, as the text of a `LinkMessage`.
/// Sparkle runs in the launcher only, so every update control in Settings ends up here.
enum UpdateRequest: Equatable {
    case check
    case setChecks(Bool)
    case setDownloads(Bool)
    case setChannel(UpdateChannel)
    /// The answer to the consent sheet.
    case consent(AutomaticUpdates)

    var text: String {
        switch self {
        case .check: "check"
        case let .setChecks(isOn): "checks:\(isOn ? 1 : 0)"
        case let .setDownloads(isOn): "downloads:\(isOn ? 1 : 0)"
        case let .setChannel(channel): "channel:\(channel.rawValue)"
        case let .consent(choice): "consent:\(Self.consentValue(choice))"
        }
    }

    private static func consentValue(_ choice: AutomaticUpdates) -> Int {
        switch choice {
        case .off: 0
        case .check: 1
        case .download: 2
        }
    }

    init?(text: String) {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count == 2 ? parts[1] : ""
        switch (parts.first ?? "", value) {
        case ("check", ""): self = .check
        case ("checks", "0"), ("checks", "1"): self = .setChecks(value == "1")
        case ("downloads", "0"), ("downloads", "1"): self = .setDownloads(value == "1")
        case ("consent", "0"), ("consent", "1"), ("consent", "2"): self = .consent(AutomaticUpdates(checks: value != "0", downloads: value == "2"))
        case ("channel", _):
            guard let channel = UpdateChannel(floeRawValue: value) else { return nil }
            self = .setChannel(channel)
        default: return nil
        }
    }
}

/// What the launcher's updater reports, for the update controls in Settings to show.
struct UpdatesState: Codable, Equatable {
    var canCheckNow = false
    var lastCheck: Date?
    var checks = false
    var downloads = false
    var channel = UpdateChannel.stable.rawValue

    var text: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init() {}

    init?(text: String) {
        guard let state = try? JSONDecoder().decode(UpdatesState.self, from: Data(text.utf8)) else { return nil }
        self = state
    }
}

extension UpdatesManager {
    /// The launcher's side: what its updater is doing.
    var state: UpdatesState {
        var state = UpdatesState()
        state.canCheckNow = canCheckNow
        state.lastCheck = lastUpdateCheckDate
        state.checks = automaticallyChecksForUpdates
        state.downloads = automaticallyDownloadsUpdates
        state.channel = updateChannel.rawValue
        return state
    }

    /// The launcher's side: does what a control in Settings asked for.
    func perform(_ request: UpdateRequest) {
        switch request {
        case .check: checkForUpdates()
        case let .setChecks(isOn): automaticallyChecksForUpdates = isOn
        case let .setDownloads(isOn): automaticallyDownloadsUpdates = isOn
        case let .setChannel(channel): updateChannel = channel
        case let .consent(choice): answerConsent(choice)
        }
    }

    /// The launcher's side: calls back whenever the state changes, for as long as the app runs.
    func observeState(_ onChange: @escaping @MainActor () -> Void) {
        withObservationTracking {
            _ = state
        } onChange: { [weak self] in
            Task { @MainActor in
                onChange()
                self?.observeState(onChange)
            }
        }
    }

    /// The settings process's side: shows what the launcher reported.
    func show(_ state: UpdatesState) {
        reported = state
        lastUpdateCheckDate = state.lastCheck
    }
}
