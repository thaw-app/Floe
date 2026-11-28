//
//  DebugModes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import CryptoKit
import SwiftUI
import ThawUI

extension NSView {
    /// Draws the view into a PNG file, for the modes that check a look without showing it.
    /// Answers whether there was anything to draw.
    @discardableResult
    func writePNG(to file: URL) -> Bool {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        return true
    }
}

/// `Floe --bench-settings`: times laying out each Settings page off screen, which catches slow page switches.
func runSettingsPageBench() -> Never {
    _ = NSApplication.shared
    let catalog = CatalogStore(snapshot: .scanningNow(includeRaycast: AppSettings.shared.includeRaycastExtensions))
    let selection = SettingsSelection()
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 820, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
    let search = SearchModel()
    window.contentView = NSHostingView(rootView: SettingsView(catalog: catalog, stores: .live(), selection: selection, search: search).thawTheme(.floe))
    window.orderFrontRegardless()
    let pages: [(String, SettingsPage)] = [("general", .general), ("applications", .applications), ("ai", .ai), ("sync", .sync), ("privacy", .privacy), ("about", .about), ("extension", .extensionPage("kill-process"))]
    for (name, page) in pages {
        let start = Date()
        selection.page = page
        // Let SwiftUI process the change, then force layout and drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        print("BENCH \(name): \(Int(Date().timeIntervalSince(start) * 1000 - 50)) ms")
        if let directory = ProcessInfo.processInfo.environment["FLOE_BENCH_DUMP"] {
            window.contentView?.writePNG(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
    runSettingsSearchBench(search: search, window: window)
    // The AI page shows one state at a time, so each is drawn on its own, on scratch settings that are never saved.
    if let directory = ProcessInfo.processInfo.environment["FLOE_BENCH_DUMP"], let scratch = UserDefaults(suiteName: "floe.bench.ai") {
        // Name, source, the API's model and key, the tool chosen by name, and the API's service.
        let states: [(String, AISource, String, String?, AITool?, AIService)] = [
            ("ai-tools", .tools, "", nil, nil, .openAI), ("ai-tool-model", .tools, "", nil, .opencode, .openAI),
            ("ai-api", .api, "small", "key-123", nil, .openAI), ("ai-api-incomplete", .api, "", nil, nil, .openAI), ("ai-api-zai", .api, "", nil, nil, .zai),
        ]
        for (name, source, aiModel, key, tool, service) in states {
            let settings = AppSettings(defaults: scratch, savesAfterEdits: false)
            settings.aiSource = source
            settings.aiModel = aiModel
            settings.aiTool = tool
            settings.aiBaseURL = service.baseURL ?? ""
            let section = Form { AISettingsSection(settings: settings, storedKey: key ?? "") }.formStyle(.grouped).frame(width: 600, height: 320)
            window.contentView = NSHostingView(rootView: section.thawTheme(.floe))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            window.contentView?.writePNG(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
    exit(0)
}

/// `Floe --icon-check`: draws each extension's icon and says how much of it was drawn, so mixed-up or invisible
/// icons show up without opening the window.
func runIconCheck() -> Never {
    _ = NSApplication.shared
    let samples: [(String, Any, String)] = ExtensionCommand.scan().uniqued(on: \.extensionName).map { command in
        (command.extensionName, command.icon ?? "", command.assetsPath)
    } + [("kill-process accessory", ["source": "cpu.svg", "tintColor": "color:PrimaryText"], ExtensionCommand.scan().first { $0.extensionName == "kill-process" }?.assetsPath ?? "")]
    for (name, value, assets) in samples {
        let renderer = ImageRenderer(content: IconView(value: value, assetsPath: assets, size: 32, waitsForImage: true).environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let image = renderer.cgImage, let data = image.dataProvider?.data as Data? else { print("\(name): no image"); continue }
        // A pixel counts as drawn when any of its four bytes is set, whatever the channel order.
        let pixels = stride(from: 0, to: data.count - 3, by: 4).filter { data[$0] | data[$0 + 1] | data[$0 + 2] | data[$0 + 3] > 8 }.count
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(8)
        if let directory = ProcessInfo.processInfo.environment["FLOE_ICON_DUMP"] {
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            try? png?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        print("\(name.padding(toLength: 24, withPad: " ", startingAt: 0)) sha=\(digest) drawn=\(pixels * 100 / max(1, data.count / 4))%")
    }
    exit(0)
}

/// `Floe --menubar [query]`: lists the menu bar items Floe can open, ranked for the query when there is one.
func runMenuBarListing(query: String) -> Never {
    let extras = MenuBarExtras.scan()
    print("MENUBAR trusted=\(MenuBarExtras.isTrusted) items=\(extras.count)")
    let ranked = query.isEmpty ? extras : extras.filter { Fuzzy.score(query, $0.name) != nil || Fuzzy.score(query, $0.ownerName) != nil }
    for extra in ranked.prefix(30) {
        print("  \(extra.name) (\(extra.ownerName)) at \(Int(extra.frame.minX)),\(Int(extra.frame.minY))")
    }
    exit(0)
}

/// `Floe --panel-snapshot <folder>`: draws the launcher in its looks and views into PNG files in the folder.
func runPanelSnapshot(path: String) -> Never {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: path)
    let model = LauncherModel(snapshot: .scanningNow(includeRaycast: AppSettings.shared.includeRaycastExtensions))
    // Scratch settings, so drawing the compact layout leaves the saved one alone.
    let settings = AppSettings(defaults: UserDefaults(suiteName: "floe.snapshot") ?? .standard)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: model.panelState.windowSize(in: settings.launcherLayout)), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: LauncherView(model: model, settings: settings).thawTheme(.floe))
    window.orderFrontRegardless()
    let resizing = model.panelWindowSizes(settings: settings).sink { window.resizeKeepingTop(to: $0) }
    let camera = PanelCamera(window: window, folder: folder)
    model.query = "co"
    camera.snapshot("root")
    settings.launcherLayout = .compact
    camera.snapshot("compact-query")
    model.query = ""
    camera.snapshot("compact")
    settings.launcherLayout = .extended
    for shape in [SearchFieldShape.capsule, .square] {
        settings.searchFieldCorners = SearchFieldCorners(shape)
        camera.snapshot("field-\(shape.rawValue)")
    }
    settings.searchFieldCorners = .rounded
    // The answer view with a canned answer: nothing is asked of any source.
    model.askAIRequest = { conversation, _ in conversation.earlier.isEmpty ? AskAI.sampleAnswer : AskAI.sampleFollowUp }
    MarkdownView.isSelectable = false
    model.openAskAI("how do tides work")
    camera.snapshot("ask-ai")
    model.closeAskAI()
    model.openMenuBarSearch()
    camera.snapshot("menubar", wait: 5)
    snapshotSeparateField(model: model, settings: settings, camera: camera)
    snapshotFollowUp(model: model, camera: camera)
    // Saved now: the edit is otherwise written a moment later, after this has exited.
    settings.save()
    resizing.cancel()
    exit(0)
}

/// Draws the launcher's window into the snapshot folder.
private struct PanelCamera {
    let window: NSWindow
    let folder: URL

    func snapshot(_ name: String, wait: TimeInterval = 1) {
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        guard window.contentView?.writePNG(to: folder.appendingPathComponent("\(name).png")) == true else { return }
        print("SNAPSHOT \(name) \(Int(window.frame.width))x\(Int(window.frame.height)) top=\(Int(window.frame.maxY))")
    }
}

private func snapshotSeparateField(model: LauncherModel, settings: AppSettings, camera: PanelCamera) {
    // The field as its own piece, last so the pictures above are drawn as they always were.
    settings.separatesSearchField = true
    camera.snapshot("separate-menubar")
    model.closeMenuBarSearch()
    model.query = "co"
    for shape in SearchFieldShape.allCases {
        settings.searchFieldCorners = SearchFieldCorners(shape)
        camera.snapshot("separate-\(shape.rawValue)")
    }
    settings.searchFieldCorners = .rounded
    settings.launcherLayout = .compact
    model.query = ""
    camera.snapshot("separate-compact")
    settings.launcherLayout = .extended
    settings.separatesSearchField = false
}

private func snapshotFollowUp(model: LauncherModel, camera: PanelCamera) {
    // A follow-up under its first answer, both canned, and last for the same reason. The look
    // settles first: a change of it draws the whole panel anew, which the answer view takes as leaving.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    model.openAskAI("how do tides work")
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    model.askAI?.draft = "and why two a day"
    model.askAI?.askFollowUp()
    camera.snapshot("ask-ai-follow-up")
    // Three presses of the up arrow: the end of the first answer over the follow-up.
    for _ in 0 ..< 3 {
        model.askAI?.scroll(by: -1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
    camera.snapshot("ask-ai-earlier")
    model.closeAskAI()
}
