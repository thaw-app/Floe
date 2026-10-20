//
//  ResidentBench.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Measures Floe's own process through its life, with the real app's services: started, after menu queries, with the
/// launcher shown and closed three times, after a trim, and settled for a minute.
enum ResidentBench {
    /// Returns this process's physical footprint in MiB, or nil if the kernel query fails.
    static func footprint() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : nil
    }

    /// Runs the opt-in benchmark and exits nonzero for excess memory.
    static func start(launcher: LauncherWindow) {
        guard let raw = ProcessInfo.processInfo.environment["FLOE_RESIDENT_BENCH"], let limit = Double(raw), limit.isFinite, limit > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            var passed = report("cold", memory: footprint(), limit: limit)
            guard readMenuAccessibility() else { print("RESIDENT FAIL: menu traversal"); finish(passed: false) }
            try? await Task.sleep(for: .seconds(2))
            passed = report("after-menu", memory: footprint(), limit: limit) && passed
            for cycle in 1 ... 3 {
                showTimed(launcher, as: "show-\(cycle)")
                try? await Task.sleep(for: .seconds(2))
                guard launcher.isVisible else { print("RESIDENT FAIL: the launcher did not show"); finish(passed: false) }
                passed = report("shown-\(cycle)", memory: footprint(), limit: limit) && passed
                launcher.hide()
                try? await Task.sleep(for: .seconds(1))
                passed = report("dismissed-\(cycle)", memory: footprint(), limit: limit) && passed
            }
            launcher.trim()
            try? await Task.sleep(for: .seconds(2))
            passed = report("trimmed", memory: footprint(), limit: limit) && passed
            let settled = await settledFootprint()
            passed = report("settled", memory: settled, limit: limit) && passed
            // How long the first show after a trim takes, while the window is made again.
            showTimed(launcher, as: "show-after-trim")
            launcher.hide()
            print(passed ? "RESIDENT PASS" : "RESIDENT FAIL: over budget")
            finish(passed: passed)
        }
    }

    /// Shows the launcher and says how long the show took, drawing included.
    private static func showTimed(_ launcher: LauncherWindow, as stage: String) {
        let started = Date()
        launcher.show()
        print("RESIDENT \(stage) \(Log.milliseconds(since: started)) ms")
    }

    /// Exercise the AppKit side of AX menu queries without requiring a CI Accessibility grant.
    /// An unused Window submenu can allocate several MiB only when its children are enumerated.
    private static func readMenuAccessibility() -> Bool {
        guard let menu = NSApp.mainMenu else { return false }
        var pending: [any NSAccessibilityProtocol] = [menu]
        var visited = Set<ObjectIdentifier>()
        while let element = pending.popLast() {
            guard visited.insert(ObjectIdentifier(element)).inserted else { continue }
            guard visited.count <= 1000 else { return false }
            _ = element.accessibilityRole()
            _ = element.accessibilityLabel()
            _ = element.accessibilityFrame()
            pending += (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol }
        }
        print("RESIDENT menu-elements \(visited.count)")
        return visited.count > 1
    }

    /// Keep the highest sample across a minute, including interval-driven background work.
    private static func settledFootprint() async -> Double? {
        var peak = 0.0
        for _ in 0 ..< 12 {
            try? await Task.sleep(for: .seconds(5))
            guard let memory = footprint() else { return nil }
            peak = max(peak, memory)
        }
        return peak
    }

    /// Stops Floe's services before returning the benchmark verdict to its harness.
    private static func finish(passed: Bool) -> Never {
        (NSApp.delegate as? AppDelegate)?.shutDown()
        exit(passed ? 0 : 1)
    }

    /// Prints a parser-readable sample but compares the unrounded value against the budget.
    private static func report(_ stage: String, memory: Double?, limit: Double) -> Bool {
        guard let memory else { print("RESIDENT FAIL: task_info"); return false }
        print("RESIDENT \(stage) \(String(format: "%.2f", memory)) MiB limit=\(limit)")
        return memory <= limit
    }
}
