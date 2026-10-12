//
//  ResidentBench.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Exercises the actual resident and its disposable process, rather than the offscreen search
/// benchmark (which deliberately does not start the app's background services).
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

    /// Runs the opt-in lifecycle benchmark and exits nonzero for missing children or excess memory.
    static func start(panel: PanelProcess) {
        guard let raw = ProcessInfo.processInfo.environment["FLOE_RESIDENT_BENCH"], let limit = Double(raw), limit.isFinite, limit > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            var passed = report("cold", memory: footprint(), limit: limit)
            guard readMenuAccessibility() else { print("RESIDENT FAIL: menu traversal"); finish(passed: false) }
            try? await Task.sleep(for: .seconds(2))
            passed = report("after-menu", memory: footprint(), limit: limit) && passed
            for cycle in 1 ... 3 {
                panel.request(.show)
                try? await Task.sleep(for: .seconds(2))
                guard panel.pid != nil else { print("RESIDENT FAIL: panel did not start"); finish(passed: false) }
                print("PANEL cycle=\(cycle) pid=\(panel.pid ?? 0)")
                panel.request(.hide)
                for _ in 0 ..< 60 where panel.pid != nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard panel.pid == nil else { print("RESIDENT FAIL: panel did not exit"); finish(passed: false) }
                passed = report("dismissed-\(cycle)", memory: footprint(), limit: limit) && passed
            }
            let settled = await settledFootprint()
            passed = report("settled", memory: settled, limit: limit) && passed
            print(passed ? "RESIDENT PASS" : "RESIDENT FAIL: over budget")
            finish(passed: passed)
        }
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

    /// Stops resident-owned services before returning the benchmark verdict to its harness.
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
