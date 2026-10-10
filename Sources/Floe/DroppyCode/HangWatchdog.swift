//
//  HangWatchdog.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Core/Support/HangWatchdog.swift, and modified: reports go to
//  Floe's logs folder under Floe's name, and what counts as a stall, a report's name and header and
//  which reports to drop are functions a test can call. A stall is counted from the oldest ping not
//  yet answered, on a clock that stops while the Mac sleeps: counted from the last answer, the seconds
//  `sample` itself takes read as a new stall and set off report after report.

import Foundation
import os

/// Catches the main thread standing still, and keeps what it was doing.
///
/// A freeze that ends in a force quit leaves nothing behind: the Dock asks spindump for a
/// hang report, spindump declines for a development build, and the crash reporter never
/// sees a process that was killed rather than crashed. So the app watches itself. A thread
/// of its own pings the main thread twice a second; when a ping goes unanswered for
/// `stallThreshold`, it runs `sample` on the process and writes every thread's stack to
/// `~/Library/Logs/Floe/hang-<date>.txt`. `sample` reads the stacks from outside,
/// so a main thread stuck in a loop or a lock is exactly what it captures. One report per
/// stall; the next stall gets one of its own.
///
/// This costs a timer on a background thread and a block on the main queue every half
/// second, nothing more, so it stays on in every build.
nonisolated enum HangWatchdog {
    private static let log = Logger(subsystem: "org.thaw.floe", category: "hang")

    /// How long the main thread may go without answering before it counts as stuck. Long
    /// enough that a heavy but finite piece of work (a big catalog scan, a slow layout pass)
    /// does not set off a report, short enough that a real freeze is caught well before the
    /// user reaches for Force Quit.
    static let stallThreshold: TimeInterval = 4

    /// How long `sample` watches the process. Short: a stuck thread does not move, and a
    /// long sample only delays the write.
    private static let sampleSeconds = 2

    /// Reports kept before the oldest is dropped, so a machine that freezes often does not
    /// fill its logs folder.
    static let keptReports = 10

    private static let state = OSAllocatedUnfairLock(initialState: State())

    struct State {
        /// When the oldest ping the main thread has not answered yet was sent; nil when none is waiting.
        var waitingSince: TimeInterval?
        var reportedThisStall = false
        var started = false
    }

    /// Seconds this Mac has been awake: it does not move while the Mac sleeps, so a night asleep is not a stall.
    private static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func start() {
        let shouldStart = state.withLock { state -> Bool in
            if state.started {
                return false
            }
            state.started = true
            return true
        }
        guard shouldStart else { return }
        let thread = Thread {
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                ping()
                check()
            }
        }
        thread.name = "hang-watchdog"
        thread.qualityOfService = .utility
        thread.start()
    }

    private static func ping() {
        state.withLock { $0.pinged(at: now) }
        DispatchQueue.main.async {
            state.withLock { $0.answer() }
        }
    }

    private static func check() {
        guard let stalledFor = state.withLock({ $0.stall(at: now) }) else { return }
        log.error("Main thread unresponsive for \(stalledFor, format: .fixed(precision: 1))s, sampling")
        let file = writeReport(stalledFor: stalledFor, in: reportsFolder(), sample: sample)
        log.error("Hang report written to \(file.path, privacy: .public)")
    }

    /// Writes what `sample` saw to a new report and drops the oldest ones. Runs on the watchdog's
    /// own thread, never the main one, so a stuck main thread cannot stop the report.
    @discardableResult
    static func writeReport(stalledFor: TimeInterval, in folder: URL, at date: Date = Date(), sample: () -> String) -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(reportName(at: date))
        let info = Bundle.main.infoDictionary
        let header = reportHeader(
            stalledFor: stalledFor,
            version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String,
            at: date
        )
        try? (header + sample()).write(to: file, atomically: true, encoding: .utf8)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in reportsToDrop(among: names) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        return file
    }

    /// Runs `sample` against this process and returns every thread's stack as it printed them.
    private static func sample() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), String(sampleSeconds), "-mayDie"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            // What sample prints is not always valid UTF-8; what can't be read is replaced, not dropped.
            // swiftlint:disable:next optional_data_string_conversion
            let body = String(decoding: data, as: UTF8.self)
            return process.terminationStatus == 0 ? body : "sample exited with status \(process.terminationStatus)\n\n" + body
        } catch {
            return "sample could not run: \(error.localizedDescription)\n"
        }
    }

    static func reportsFolder(
        library: URL? = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
    ) -> URL {
        (library ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")).appendingPathComponent("Logs/Floe", isDirectory: true)
    }

    /// A report's file name. The date sorts as text, so the oldest report is the first by name.
    static func reportName(at date: Date) -> String {
        "hang-\(ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")).txt"
    }

    static func reportHeader(stalledFor: TimeInterval, version: String?, build: String?, at date: Date) -> String {
        """
        Floe main thread unresponsive for \(String(format: "%.1f", stalledFor))s
        Version \(version ?? "?") (\(build ?? "?"))
        Sampled at \(date)


        """
    }

    /// The oldest reports beyond the ones kept, among a folder's file names. Other files are left alone.
    static func reportsToDrop(among names: [String], keeping kept: Int = keptReports) -> [String] {
        let reports = names.filter { $0.hasPrefix("hang-") && $0.hasSuffix(".txt") }.sorted()
        return Array(reports.dropLast(max(kept, 0)))
    }
}

nonisolated extension HangWatchdog.State {
    /// A ping was sent. The wait is counted from the first one still unanswered.
    mutating func pinged(at uptime: TimeInterval) {
        waitingSince = waitingSince ?? uptime
    }

    /// The main thread answered a ping: any stall is over, and the next one gets a report of its own.
    mutating func answer() {
        waitingSince = nil
        reportedThisStall = false
    }

    /// How long a ping has gone unanswered, when that is a stall no report was written for yet.
    /// Asking marks the stall as reported.
    mutating func stall(at uptime: TimeInterval, threshold: TimeInterval = HangWatchdog.stallThreshold) -> TimeInterval? {
        guard let waitingSince, uptime - waitingSince >= threshold, !reportedThisStall else { return nil }
        reportedThisStall = true
        return uptime - waitingSince
    }
}
