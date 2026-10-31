//
//  SearchBench.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

private func milliseconds(_ work: () -> Void) -> Int {
    let start = Date()
    work()
    return Int(Date().timeIntervalSince(start) * 1000)
}

/// What Activity Monitor calls Memory, read from inside since `footprint` cannot attach to an unsigned debug build.
private func footprintMegabytes() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// Adds up the time the main run loop spends awake, which is where work finished off the main thread lands.
private final class RunLoopBusyTime {
    private(set) var milliseconds = 0.0
    private var wokeAt: CFAbsoluteTime?

    init() {
        // Leaving the loop ends a stretch too, or the timed work after it would be counted.
        let activities: CFRunLoopActivity = [.afterWaiting, .beforeWaiting, .exit]
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities.rawValue, true, 0) { [weak self] _, activity in
            guard let self else { return }
            if activity == .afterWaiting {
                wokeAt = CFAbsoluteTimeGetCurrent()
            } else if let woke = wokeAt {
                milliseconds += (CFAbsoluteTimeGetCurrent() - woke) * 1000
                wokeAt = nil
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}

/// The catalog, scanned a part at a time with each part's time printed.
private func timedCatalog() -> CatalogSnapshot {
    var apps: [AppEntry] = []
    var commands: [ExtensionCommand] = []
    var scripts = ScriptScan(commands: [], failures: [])
    var panes: [SystemSettingsPane] = []
    print("SCAN apps \(milliseconds { apps = AppEntry.scan() }) ms (\(apps.count))")
    print("SCAN commands \(milliseconds { commands = ExtensionCommand.scan(includeRaycast: true) }) ms (\(commands.count))")
    print("SCAN scripts \(milliseconds { scripts = ScriptCommand.scan() }) ms (\(scripts.commands.count))")
    var extras = 0
    print("SCAN menu bar items \(milliseconds { extras = MenuBarExtras.scan().count }) ms (\(extras))")
    print("SCAN settings panes \(milliseconds { panes = SystemSettingsPane.scan() }) ms (\(panes.count))")
    return CatalogSnapshot(apps: apps, commands: commands, scripts: scripts.commands, scriptFailures: scripts.failures, settingsPanes: panes)
}

/// The saved settings, or scratch ones when FLOE_BENCH_SEPARATE is set: 1 draws the search field as its own piece, 0 does not.
private func benchSettings() -> AppSettings {
    guard let separate = ProcessInfo.processInfo.environment["FLOE_BENCH_SEPARATE"], let scratch = UserDefaults(suiteName: "floe.bench.separate") else {
        return .shared
    }
    let settings = AppSettings(defaults: scratch, savesAfterEdits: false)
    settings.separatesSearchField = separate == "1"
    return settings
}

/// `Floe --bench-search [query ...]` times the catalog scan and each keystroke of a query, drawn off screen.
func runSearchBench(queries: [String]) -> Never {
    _ = NSApplication.shared
    let model = LauncherModel(snapshot: timedCatalog())
    model.canAskAI = AskAI.availabilityCheck { AIAnswer.isAvailable }
    let frame = NSRect(origin: NSPoint(x: -4000, y: -4000), size: model.panelState.windowSize(in: .extended))
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    // Timed: the work one change costs. The run loop's turn afterwards is not, since it mostly waits.
    func render() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
    func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    print("FIRST RENDER \(milliseconds { window.contentView = NSHostingView(rootView: LauncherView(model: model, settings: benchSettings()).thawTheme(.floe)); window.orderFrontRegardless(); render() }) ms")
    settle()
    for query in queries.isEmpty ? ["safari", "settings", "ask why is the sky blue"] : queries {
        var typed = ""
        var times: [String] = []
        for character in query {
            typed.append(character)
            // The search and the drawing apart: "s=3+9" is 3 ms finding rows and 9 ms drawing them.
            let search = milliseconds { model.query = typed }
            times.append("\(typed.suffix(1))=\(search)+\(milliseconds { render() })")
            settle()
        }
        model.query = ""
        render()
        settle()
        print("TYPE \"\(query)\" ms per key: \(times.joined(separator: " ")) rows=\(model.results.count)")
    }
    // Arrowing down the browse list, which is what moving through results costs.
    let steps = min(60, max(model.results.count - 1, 0))
    var moves: [Int] = []
    let busy = RunLoopBusyTime()
    for step in 0 ..< steps {
        moves.append(milliseconds { model.selection = step + 1; render() })
        settle()
    }
    print("MOVE \(steps) rows, ms per row: average \(moves.reduce(0, +) / max(steps, 1)), worst \(moves.max() ?? 0)")
    print("MOVE each: \(moves.map(String.init).joined(separator: " "))")
    print("MOVE settle: main thread busy \(String(format: "%.1f", busy.milliseconds / Double(max(steps, 1)))) ms per row between steps")
    print("FOOTPRINT \(String(format: "%.1f", footprintMegabytes())) MB")
    // FLOE_BENCH_LINGER=<seconds> keeps the process around so `footprint` and `heap` can read it.
    if let seconds = ProcessInfo.processInfo.environment["FLOE_BENCH_LINGER"].flatMap(Double.init) {
        print("LINGER pid \(ProcessInfo.processInfo.processIdentifier) for \(Int(seconds)) s")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    exit(0)
}

/// Part of `--bench-settings`: types into the settings search and times each key, the matching and the drawing apart.
@MainActor
func runSettingsSearchBench(search: SearchModel, window: NSWindow) {
    for query in ["appearance", "hotkey", "clip"] {
        var typed = ""
        var times: [String] = []
        for character in query {
            typed.append(character)
            let match = milliseconds { search.searchText = typed }
            let draw = milliseconds {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
            times.append("\(character)=\(match)+\(draw)")
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        print("BENCH search \"\(query)\" ms per key: \(times.joined(separator: " ")) results=\(search.resultCount)")
        search.searchText = ""
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
