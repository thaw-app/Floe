//
//  SearchBarTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import SwiftUI
import Testing

/// The search bar's spinner on screen: loading shows it only after the gate's wait, and loading's end
/// takes it away at once.
@MainActor
struct SearchBarTests {
    private final class Probe: ObservableObject {
        @Published var isLoading = false
    }

    private struct SearchBarProbe: View {
        @ObservedObject var probe: Probe

        var body: some View {
            SearchBar(placeholder: "Search", text: .constant(""), focusToken: 0, isLoading: probe.isLoading) { EmptyView() }
        }
    }

    /// The probe's view in a window that is never shown, since SwiftUI commits its updates only
    /// once the view lives in a window.
    private final class Harness {
        let host: NSHostingView<SearchBarProbe>
        let probe = Probe()
        private let window: NSWindow

        init() {
            host = NSHostingView(rootView: SearchBarProbe(probe: probe))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 44), styleMask: .borderless, backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = window.contentLayoutRect
        }

        func layout() {
            host.layoutSubtreeIfNeeded()
        }

        /// Lays the view out first, so what is checked is what is drawn now.
        func showsSpinner() -> Bool {
            layout()
            return Self.hasSpinner(host)
        }

        private static func hasSpinner(_ view: NSView) -> Bool {
            view is NSProgressIndicator || view.subviews.contains { hasSpinner($0) }
        }
    }

    /// Waits until the condition holds, since a busy test run delays the main actor's turns.
    private func settle(until condition: () -> Bool) async {
        for _ in 0 ..< 300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func loadingShowsTheSpinnerOnlyAfterTheWait() async {
        let harness = Harness()
        harness.layout()

        let start = ContinuousClock.now
        harness.probe.isLoading = true
        harness.layout()
        try? await Task.sleep(for: .milliseconds(100))
        let early = harness.showsSpinner()
        // A busy run only makes the spinner later, so its absence is checked only while the wait can't have passed.
        if ContinuousClock.now - start < .milliseconds(200) {
            #expect(!early, "the spinner waits for loading to hold before it shows")
        }
        await settle(until: { harness.showsSpinner() })
        #expect(harness.showsSpinner())
    }

    @Test func theEndOfLoadingTakesTheSpinnerAwayAtOnce() async {
        let harness = Harness()
        harness.layout()

        harness.probe.isLoading = true
        await settle(until: { harness.showsSpinner() })
        #expect(harness.showsSpinner(), "the spinner shows while loading holds")
        harness.probe.isLoading = false
        await settle(until: { !harness.showsSpinner() })
        #expect(!harness.showsSpinner(), "loading's end takes the spinner away at once")
    }
}
