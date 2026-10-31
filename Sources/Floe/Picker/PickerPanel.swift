//
//  PickerPanel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// `Floe --pick`: a short-lived process that shows the lines on standard input in the launcher's
/// panel and prints the chosen one. It never builds the app delegate, so none of the app starts.
enum PickerMode {
    static func run(_ options: DebugOptions) -> Never {
        guard isatty(STDIN_FILENO) == 0 else {
            FileHandle.standardError.write(Data("\(PickList.usage)\n".utf8))
            exit(PickExit.usage.rawValue)
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        // Input that is not UTF-8 is read as Latin-1, which accepts any bytes, so the list still shows.
        let input = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
        let items = PickList.items(from: input)
        guard !items.isEmpty else { exit(PickExit.cancelled.rawValue) }

        let session = PickSession(items: items, prompt: options.prompt ?? String(localized: "Search…", bundle: .floe), query: options.query ?? "")
        session.finish = { item in
            guard let item else { exit(PickExit.cancelled.rawValue) }
            print(PickList.output(for: item, printsIndex: options.index))
            exit(PickExit.chosen.rawValue)
        }
        let environment = ProcessInfo.processInfo.environment
        if environment["FLOE_PICK_AUTO"] != nil {
            session.finish(session.selected)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = PickPanelController(session: session)
        if let path = environment["FLOE_PICK_SNAPSHOT"] {
            controller.snapshot(to: URL(fileURLWithPath: path))
            exit(PickExit.cancelled.rawValue)
        }
        // Shown from inside the run loop: a window made key before it starts does not get the keyboard.
        DispatchQueue.main.async { controller.show() }
        withExtendedLifetime(controller) { app.run() }
        exit(PickExit.cancelled.rawValue)
    }
}

/// What the panel shows and which row is selected.
final class PickSession: ObservableObject {
    let items: [PickItem]
    let prompt: String
    @Published var query: String {
        didSet {
            guard query != oldValue else { return }
            results = PickList.matches(items, query: query)
            selection = 0
        }
    }

    @Published private(set) var results: [PickItem]
    @Published var selection = 0
    /// Ends the process: the chosen item, or nil when the picker is dismissed.
    var finish: (PickItem?) -> Void = { _ in
        // Set by `PickerMode.run` before the panel is shown.
    }

    init(items: [PickItem], prompt: String, query: String) {
        self.items = items
        self.prompt = prompt
        self.query = query
        results = PickList.matches(items, query: query)
    }

    var selected: PickItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func move(by delta: Int) {
        selection = PickList.selection(selection, movedBy: delta, count: results.count)
    }

    func select(_ item: PickItem) {
        selection = results.firstIndex(of: item) ?? selection
    }

    /// Return with nothing matching keeps the panel open, so the query can be corrected.
    func choose() {
        if let selected {
            finish(selected)
        }
    }
}

/// The picker's window: the launcher's panel, in the launcher's place, with the keys the launcher's list takes.
final class PickPanelController: NSObject, NSWindowDelegate {
    private let session: PickSession
    private let panel: LauncherPanel
    private var keyMonitor: Any?
    private var focusObservation: NSKeyValueObservation?

    init(session: PickSession) {
        self.session = session
        panel = LauncherPanel(size: LauncherPanelState().windowSize(in: .extended))
        super.init()
        panel.contentView = NSHostingView(rootView: PickView(session: session))
        // A focused field selects its text, and typing would then replace the starting query instead of adding to it.
        focusObservation = panel.observe(\.firstResponder) { [weak self] panel, _ in
            // Safe: KVO calls back on the thread that made the change, and a window's first responder changes on the main one.
            MainActor.assumeIsolated {
                guard let editor = panel.firstResponder as? NSTextView else { return }
                self?.focusObservation = nil
                DispatchQueue.main.async { editor.moveToEndOfDocument(nil) }
            }
        }
    }

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(LauncherPanelState().origin(in: frame, panelSize: panel.frame.size))
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // While an input method is composing, Return and Escape belong to it.
        if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true {
            return false
        }
        switch event.keyCode {
        case 36, 76:
            session.choose()
        case 53:
            session.finish(nil)
        default:
            guard let delta = Shortcuts.navigationDelta(event.keyCode) else { return false }
            session.move(by: delta)
        }
        return true
    }

    func windowDidResignKey(_: Notification) {
        // Checked a turn later, once focus has settled, as the launcher does.
        DispatchQueue.main.async { [self] in
            if !panel.isKeyWindow {
                session.finish(nil)
            }
        }
    }

    /// Draws the panel off screen, so its look can be checked without it taking the keyboard.
    func snapshot(to file: URL) {
        panel.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        panel.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        panel.contentView?.writePNG(to: file)
    }
}

struct PickView: View {
    @ObservedObject var session: PickSession
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let size = LauncherPanelState().contentSize(in: .extended)
        let look = settings.launcherLook(for: colorScheme)
        // The picker's field is always the rounded one, so its piece is too.
        let pieces = settings.separatesSearchField ? PanelPieces(look: look, fieldShape: .rounded, heights: LauncherPanelState().pieceHeights(in: .extended)) : nil
        GlassEffectContainer {
            PanelSections {
                SearchBar(placeholder: session.prompt, text: $session.query, focusToken: 0) { EmptyView() }
            } content: {
                if session.results.isEmpty {
                    ThawEmptyState(systemImage: "magnifyingglass", title: .floe("Nothing matches"), caption: .floe("Try fewer letters."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
                bottomBar
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .modifier(PanelLook(look: look, pieces: pieces))
        .padding(LauncherView.margin)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy, so ten thousand lines cost only the rows on screen.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.results) { item in
                        PickRow(title: item.title, detail: item.detail, selected: item == session.selected)
                            .id(item.id)
                            .onTapGesture { session.select(item) }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { session.finish(item) })
                    }
                }
            }
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .onChange(of: session.selection) {
                if let selected = session.selected {
                    proxy.scrollTo(selected.id)
                }
            }
        }
    }

    private var bottomBar: some View {
        PanelBottomBar {
            Text(PickList.countLabel(shown: session.results.count, total: session.items.count, isFiltered: !session.query.isEmpty))
                .foregroundStyle(.secondary)
                .padding(.leading, 5)
            Spacer(minLength: 0)
            ShortcutHintButton(title: String(localized: "Cancel", bundle: .floe)) { session.finish(nil) } hint: {
                KeyCapView(text: "esc")
            }
            if session.selected != nil {
                ShortcutHintButton(title: String(localized: "Choose", bundle: .floe, comment: "A verb on a button: pick the selected line.")) { session.choose() } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
    }
}

/// `PaletteRow` without its icon column: a line of input has no icon, and the empty column would indent every row.
private struct PickRow: View {
    let title: String
    let detail: String?
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: title)
                .lineLimit(1)
                // Paths differ at their ends, so the middle is what gives way.
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let detail {
                Text(verbatim: detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(ThawType.body)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .modifier(SearchRowBackground(selected: selected))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
