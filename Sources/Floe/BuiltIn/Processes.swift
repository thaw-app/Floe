//
//  Processes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import Darwin
import Foundation
import Subprocess

/// A process of the user's that is running now.
nonisolated struct RunningProcess: Hashable, Sendable {
    let pid: Int32
    let path: String
    /// The memory it holds, in bytes, as Activity Monitor counts it.
    let memory: UInt64

    var name: String {
        (path as NSString).lastPathComponent
    }

    /// The application the program belongs to, when it runs from inside one.
    var bundlePath: String? {
        path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" }
    }
}

/// `kill` and a name lists the running processes that match, to quit one by looking at it and not by pattern.
nonisolated enum Processes {
    static let keyword = "kill"
    static let limit = 8

    static let portKeyword = "port"

    /// The port typed after `port`, or nil for any other search.
    static func port(in query: String) -> Int? {
        let words = query.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count == 2, words[0].lowercased() == portKeyword, words[1].count >= 2, words[1].allSatisfy(\.isNumber),
              let port = Int(words[1]), (1 ... 65535).contains(port) else { return nil }
        return port
    }

    /// The process numbers in what `lsof -t` printed, each once.
    static func pids(in output: String) -> [Int32] {
        Array(output.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }.uniqued())
    }

    private static let listeners = TimedCache<Int, [Int32]>()

    /// The processes listening on a port, asked of `lsof`. Kept for two seconds, as the list of processes is.
    @concurrent
    static func listening(on port: Int, now: Date = Date()) async -> [Int32] {
        await listeners.value(for: port, lasting: 2, now: now) {
            // lsof prints nothing and ends with 1 when no process listens, so only what it printed is read.
            let lsof = try? await Subprocess.run(
                .path("/usr/sbin/lsof"),
                arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"],
                output: .string(limit: 1 << 20),
                error: .discarded
            )
            return pids(in: lsof?.standardOutput ?? "")
        }
    }

    /// The name typed after the keyword, or nil for any other search.
    static func name(in query: String) -> String? {
        let words = query.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard words.count == 2, words[0].lowercased() == keyword else { return nil }
        let name = words[1].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// The processes whose name or path holds the typed text, those named so first, then the ones holding most memory.
    static func matching(_ typed: String, in processes: [RunningProcess], excluding own: Int32 = getpid()) -> [RunningProcess] {
        processes
            .filter { $0.pid != own && $0.pid > 1 && $0.path.localizedCaseInsensitiveContains(typed) }
            .map { (process: $0, named: $0.name.localizedCaseInsensitiveContains(typed)) }
            .min(count: limit) { ($0.named ? 0 : 1, $1.process.memory, $0.process.pid) < ($1.named ? 0 : 1, $0.process.memory, $1.process.pid) }
            .map(\.process)
    }

    /// What sets one row apart from another of the same name: its number and what it holds.
    static func label(for process: RunningProcess) -> String {
        let memory = ByteCountFormatter.string(fromByteCount: Int64(process.memory), countStyle: .memory)
        return String(localized: "PID \(String(process.pid)) · \(memory)", bundle: .floe, comment: "PID is a process's number and stays as written. The second placeholder is an amount of memory, such as 120 MB.")
    }

    /// Asks the process to quit, or with `force` ends it where it stands. Answers whether the system took the request.
    static func end(_ process: RunningProcess, force: Bool) -> Bool {
        kill(process.pid, force ? SIGKILL : SIGTERM) == 0
    }

    private static let listing = TimedCache<Int, [RunningProcess]>()

    /// Forgets the lists, after a process was ended: the next search reads them again.
    static func forget() {
        listeners.forget()
        listing.forget()
    }

    /// The running processes this user may look at. The list is kept for two seconds: the search asks at every key.
    static func running(now: Date = Date()) -> [RunningProcess] {
        listing.value(for: 0, lasting: 2, now: now) {
            var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
            let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
            var path = [CChar](repeating: 0, count: 4096)
            return pids.prefix(max(0, count)).compactMap { process($0, path: &path) }
        }
    }

    /// One process with where it runs from and the memory it holds. `path` is room to write into, reused for each.
    private static func process(_ pid: pid_t, path: inout [CChar]) -> RunningProcess? {
        // Another user's process answers with nothing, and could not be ended anyway.
        let length = pid > 0 ? Int(proc_pidpath(pid, &path, UInt32(path.count))) : 0
        guard length > 0, let location = String(bytes: path.prefix(length).map { UInt8(bitPattern: $0) }, encoding: .utf8) else { return nil }
        return RunningProcess(pid: pid, path: location, memory: memory(of: pid))
    }

    /// What Activity Monitor calls a process's Memory, in bytes. Zero for one that cannot be asked.
    static func memory(of pid: pid_t) -> UInt64 {
        var usage = rusage_info_v2()
        let read = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return read == 0 ? usage.ri_phys_footprint : 0
    }
}
