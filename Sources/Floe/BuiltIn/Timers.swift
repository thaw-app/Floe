//
//  Timers.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import UserNotifications

/// What `timer` and a length of time asks for: a countdown that long, with the words after it as its label.
nonisolated struct TimerDraft: Hashable, Sendable {
    var duration: TimeInterval
    var label = ""

    static let keyword = "timer"
    /// A countdown longer than a day is a reminder, and those are Reminders'.
    static let longest: TimeInterval = 24 * 3600

    /// `timer 5 min tea` asks for five minutes, labelled tea. Nil for a length that is zero or over a day.
    static func request(in query: String) -> TimerDraft? {
        let words = query.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard words.count == 2, words[0].lowercased() == keyword, let length = TimeLength.leading(String(words[1])) else { return nil }
        guard length.seconds > 0, length.seconds <= longest else { return nil }
        return TimerDraft(duration: length.seconds, label: length.rest.replacing(#/^for\s+/#.ignoresCase(), with: ""))
    }

    /// What the timer is called: its label, or how long it runs.
    var name: String {
        label.isEmpty ? TimeLength.text(duration) : label
    }
}

/// A length of time as it is typed: `10 minutes`, `25m`, `1h 30m`, `90s`.
nonisolated enum TimeLength {
    /// The length a text starts with and the words after it. A number alone is minutes.
    static func leading(_ text: String) -> (seconds: TimeInterval, rest: String)? {
        let part = #/\s*(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)(?![a-z])/#.ignoresCase()
        var rest = text[...]
        var seconds: TimeInterval = 0
        var found = false
        while let match = rest.prefixMatch(of: part), let count = Double(match.1) {
            seconds += count * unit(String(match.2))
            rest = rest[match.range.upperBound...]
            found = true
        }
        if !found {
            guard let match = text.prefixMatch(of: #/\s*(\d+)(?![\w.,:])/#), let minutes = Double(match.1) else { return nil }
            seconds = minutes * 60
            rest = text[match.range.upperBound...]
        }
        return (seconds, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func unit(_ word: String) -> TimeInterval {
        switch word.lowercased().first {
        case "h": 3600
        case "m": 60
        default: 1
        }
    }

    /// How long, as it is read: 10 min, or 1 hr, 30 min.
    static func text(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated).locale(locale))
    }

    /// What a clock counting down shows: 4:12, or 1:04:12 from an hour up.
    static func clock(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let left = max(0, seconds.rounded(.up))
        return Duration.seconds(left).formatted(.time(pattern: left >= 3600 ? .hourMinuteSecond : .minuteSecond).locale(locale))
    }
}

/// A countdown Floe is holding. It lives in the launcher's memory and ends with it.
nonisolated struct RunningTimer: Hashable, Identifiable, Sendable {
    var id = UUID()
    var label = ""
    var duration: TimeInterval
    var ends: Date

    var name: String {
        label.isEmpty ? TimeLength.text(duration) : label
    }

    /// Beside the name: the time left, such as 4:12 left.
    func left(now: Date = Date(), locale: Locale = .current) -> String {
        let clock = TimeLength.clock(ends.timeIntervalSince(now), locale: locale)
        return String(localized: "\(clock) left", bundle: .floe, comment: "Beside a running timer. The placeholder is the time left on its clock, such as 4:12.")
    }
}

/// A row about a timer: the one that starts it, or one that is counting down.
enum TimerRow: Hashable {
    case draft(TimerDraft)
    case running(RunningTimer)

    var id: String {
        switch self {
        case .draft: "timer-draft"
        case let .running(timer): "timer:\(timer.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case let .draft(draft): String(localized: "Timer: \(TimeLength.text(draft.duration))", bundle: .floe, comment: "The title of the row that starts a timer. The placeholder is how long it runs, such as 10 min.")
        case let .running(timer): timer.name
        }
    }

    /// Beside the title: the label a new timer was given, or the time a running one has left. Nil when there is nothing to say.
    var label: String? {
        switch self {
        case let .draft(draft): draft.label.isEmpty ? nil : draft.label
        case let .running(timer): timer.left()
        }
    }
}

/// What tells the user a timer ended, and what waits for that moment.
enum TimerAlerts {
    /// Lets a notification show while Floe is the app in front, which macOS otherwise keeps quiet.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }

    private static let presenter = Presenter()

    /// Whether Floe may post notifications. macOS asks the user the first time.
    static func requestAccess() async -> Bool {
        // Run outside its app bundle, as a development build is, Floe has no notifications to ask for.
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        return await (try? center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(_ timer: RunningTimer) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Timer ended", bundle: .floe, comment: "The title of the notification a timer posts when it ends.")
        content.body = timer.name
        content.sound = .default
        // A timer the user set is worth a Focus. Without the entitlement the system treats it as an ordinary one.
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: nil))
    }

    /// Calls back after that long, and answers with what calls the wait off. The clock keeps counting while the Mac sleeps.
    static func wait(_ seconds: TimeInterval, then: @escaping () -> Void) -> () -> Void {
        let task = Task {
            try? await Task.sleep(for: .seconds(seconds), clock: .continuous)
            if !Task.isCancelled {
                then()
            }
        }
        return { task.cancel() }
    }
}

/// `timer` and a length of time leads the results with the row that starts the countdown.
struct TimerSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard context.text(after: TimerDraft.keyword) != nil, let draft = TimerDraft.request(in: context.trimmed) else { return SearchContribution() }
        return SearchContribution(pinned: [RootResult(item: .timer(.draft(draft)), section: nil)])
    }
}

/// `timers`: the countdowns that are running, the one that ends first on top.
struct TimersSearchScope: SearchScope {
    let keyword = "timers"
    let title = String(localized: "Timers", bundle: .floe)
    let emptyTitle = String(localized: "No timer is running", bundle: .floe)

    /// The word alone lists them all, as `receipts` does.
    func text(in context: SearchContext) -> String? {
        if let text = context.text(after: keyword) {
            return text
        }
        return context.trimmed.lowercased() == keyword ? "" : nil
    }

    func results(for text: String, context: SearchContext) -> [RootItem] {
        let words = text.lowercased().split(separator: " ")
        return context.timers
            .filter { timer in words.allSatisfy { timer.name.lowercased().contains($0) } }
            .sorted { $0.ends < $1.ends }
            .map { RootItem.timer(.running($0)) }
    }
}
