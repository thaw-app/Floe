//
//  ThawAppearanceFollower.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine
import Foundation

/// Asks Thaw for its menu bar look and keeps the answers, while the launcher follows Thaw's appearance.
/// The answers sit beside the user's own appearance settings, never in them. Main thread only.
final class ThawAppearanceFollower: ObservableObject {
    static let shared = ThawAppearanceFollower()

    /// The host of the `floe://` link Thaw opens with its answer.
    static let callbackHost = IncomingLink.thawAppearanceHost
    /// Thaw posts this, with nothing attached, whenever its look changes.
    static let changeNotification = Notification.Name("com.stonerl.Thaw.appearanceDidChange")
    /// How long Thaw has to answer. It answers at once when it answers at all.
    static let timeout: TimeInterval = 5

    enum Status: String, Equatable {
        case idle
        case following
        /// Thaw was asked and stayed silent: it lacks the operation, or does not trust this build of Floe.
        case noAnswer
        /// Asking would start Thaw, so it is not asked.
        case notRunning
        /// Thaw answered with an error, a later version, or something that does not decode.
        case unreadable
    }

    /// The outside world, replaceable in tests.
    struct Environment {
        var open: (URL) -> Bool
        var isThawRunning: () -> Bool
        var newRequestId: () -> String
        var now: () -> Date
        var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void

        static let live = Environment(
            open: { NSWorkspace.shared.open($0) },
            isThawRunning: {
                guard let id = Thaw.applicationURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }) else { return false }
                return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            },
            // A version 4 UUID is 122 random bits from the system's generator.
            newRequestId: { UUID().uuidString },
            now: Date.init,
            schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } }
        )
    }

    private struct Pending {
        let requestId: String
        let deadline: Date
    }

    @Published private(set) var status = Status.idle

    private static let defaultsKey = "thawAppearance"
    private let settings: AppSettings
    private let defaults: UserDefaults
    private let environment: Environment
    private var pending: Pending?
    /// A reason to fetch arrived while a request was out, so one more follows its answer.
    private var isStale = false
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings = .shared, defaults: UserDefaults = .standard, environment: Environment = .live) {
        self.settings = settings
        self.defaults = defaults
        self.environment = environment
        // The last answers come back at launch, so the panel opens in Thaw's look before Thaw is asked again.
        loadSaved()
    }

    private func loadSaved() {
        let saved = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode([ThawAppearance].self, from: $0) }
        for appearance in saved ?? [] where appearance.version == ThawAppearance.supportedVersion {
            settings.thawAppearances[appearance.colorScheme] = appearance
        }
    }

    /// In the settings process, which never asks Thaw itself: shows what the launcher's follower reports.
    func mirror(_ status: Status) {
        loadSaved()
        self.status = status
    }

    static func requestURL(requestId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "thaw"
        components.host = ThawAppearanceResponse.operation
        components.queryItems = [
            URLQueryItem(name: "callback", value: "floe://\(callbackHost)"),
            URLQueryItem(name: "requestId", value: requestId),
        ]
        return components.url
    }

    /// Fetches now if the switch is on, and again on every reason the look may have changed.
    func start() {
        let refresh: (Any) -> Void = { [weak self] _ in self?.refresh() }
        // Duplicates go first: a reload of settings saved by the settings process sends the same value again.
        settings.$followsThawAppearance.removeDuplicates().dropFirst()
            // After the publisher's willSet, so the switch reads its new value.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in
                if isOn {
                    self?.refresh()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
        DistributedNotificationCenter.default().publisher(for: Self.changeNotification)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: refresh)
            .store(in: &cancellables)
        // Thaw answers for one colour scheme, so a switch between light and dark needs the other one.
        NSApp.publisher(for: \.effectiveAppearance).dropFirst()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: refresh)
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .filter { note in
                let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                return launched?.bundleURL?.path == Thaw.applicationURL?.path
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: refresh)
            .store(in: &cancellables)
        self.refresh()
    }

    /// Asks Thaw for its look. One request is out at a time; a call during one asks again after it.
    func refresh() {
        guard settings.followsThawAppearance else { return }
        if let pending, environment.now() < pending.deadline {
            isStale = true
            return
        }
        pending = nil
        isStale = false
        guard environment.isThawRunning() else {
            status = .notRunning
            return
        }
        let requestId = environment.newRequestId()
        guard let url = Self.requestURL(requestId: requestId), environment.open(url) else {
            status = .noAnswer
            return
        }
        pending = Pending(requestId: requestId, deadline: environment.now().addingTimeInterval(Self.timeout))
        environment.schedule(Self.timeout) { [weak self] in self?.expire(requestId) }
    }

    /// Takes a `floe://thaw-appearance` link. Any app can open one, so only the answer to the request
    /// that is out is read, once and in time; everything else is dropped.
    func receive(_ url: URL) {
        guard let pending,
              environment.now() < pending.deadline,
              let body = ThawAppearanceResponse.body(of: url),
              let header = ThawAppearanceResponse.header(of: body),
              header.requestId == pending.requestId,
              header.operation == ThawAppearanceResponse.operation
        else { return }
        self.pending = nil
        if let appearance = try? ThawAppearanceResponse.appearance(in: body) {
            settings.thawAppearances[appearance.colorScheme] = appearance
            if let data = try? JSONEncoder().encode(Array(settings.thawAppearances.values)) {
                defaults.set(data, forKey: Self.defaultsKey)
            }
            status = .following
        } else {
            status = .unreadable
        }
        if isStale {
            refresh()
        }
    }

    /// The timeout: the last look stays, and Settings says Thaw did not answer.
    private func expire(_ requestId: String) {
        guard pending?.requestId == requestId else { return }
        pending = nil
        isStale = false
        status = .noAnswer
    }

    private func stop() {
        pending = nil
        isStale = false
        status = .idle
    }
}
