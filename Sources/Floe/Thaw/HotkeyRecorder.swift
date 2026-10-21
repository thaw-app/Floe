//
//  HotkeyRecorder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to the launcher: binds to an optional KeyCombination instead of Thaw's Hotkey model,
//  and uses an NSEvent monitor directly. Recording suspends `HotkeyRegistry` through `onRecordingChange`.
//  The control has a fixed size, so every recorder is the same width whatever its label.

import AppKit
import SwiftUI
import ThawUI

struct HotkeyRecorder<Label: View>: View {
    /// What the control is showing at the moment.
    private enum Phase {
        /// Waiting for the user to type a combination.
        case listening
        /// A combination is assigned.
        case assigned(KeyCombination)
        /// No combination is assigned.
        case empty
    }

    @Binding private var keyCombination: KeyCombination?
    private let onRecordingChange: (Bool) -> Void
    private let label: Label

    @State private var capture = KeyCapture()

    init(
        keyCombination: Binding<KeyCombination?>,
        onRecordingChange: @escaping (Bool) -> Void = { _ in
            // Nothing to suspend.
        },
        @ViewBuilder label: () -> Label
    ) {
        self._keyCombination = keyCombination
        self.onRecordingChange = onRecordingChange
        self.label = label()
    }

    private var phase: Phase {
        if capture.isListening {
            return .listening
        }
        if let keyCombination {
            return .assigned(keyCombination)
        }
        return .empty
    }

    var body: some View {
        LabeledContent {
            segments
        } label: {
            label
        }
        .alert(
            "macOS already uses this shortcut",
            isPresented: $capture.isShowingReservedWarning
        ) {
            Button("Choose Another") {
                capture.isShowingReservedWarning = false
            }
        } message: {
            Text("Record a different one, or turn this one off in System Settings → Keyboard → Keyboard Shortcuts.")
        }
        .onDisappear { capture.stop() }
    }

    private var segments: some View {
        HStack(spacing: 1) {
            displaySegment
            actionSegment
        }
        // Fixed, unlike Thaw's: the segments are shapes and take whatever a form row offers,
        // which is less beside a label that carries a description.
        .frame(width: 160, height: SegmentButtonStyle.outerRadius * 2)
    }

    private func startCapture() {
        capture.start(onRecordingChange: onRecordingChange) { keyCombination = $0 }
    }

    /// The wider half, which reports the current state and starts a recording.
    private var displaySegment: some View {
        Button {
            switch phase {
            case .listening: capture.stop()
            case .assigned, .empty: startCapture()
            }
        } label: {
            switch phase {
            case .listening:
                Text("Type Shortcut")
            case let .assigned(keyCombination):
                Text(keyCombination.displayValue)
            case .empty:
                Text("Record Shortcut")
            }
        }
        .buttonStyle(SegmentButtonStyle(side: .leading, isHighlighted: capture.isListening))
    }

    /// The square half, whose meaning depends on the phase: back out of a
    /// recording, throw away an assigned combination, or start a recording.
    private var actionSegment: some View {
        Button {
            switch phase {
            case .listening: capture.stop()
            case .assigned: keyCombination = nil
            case .empty: startCapture()
            }
        } label: {
            actionSegmentLabel
        }
        .buttonStyle(SegmentButtonStyle(side: .trailing, isHighlighted: false))
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var actionSegmentLabel: some View {
        // The insets differ because the symbols are drawn at different
        // optical weights and would not otherwise look evenly sized.
        let (symbol, description, inset): (String, String, CGFloat) = switch phase {
        case .listening: ("escape", String(localized: "Cancel", bundle: .floe, comment: "A button that stops what is under way, such as recording a keyboard shortcut."), 6)
        // Its own key: the glass style named Clear is another word in most languages.
        case .assigned: ("xmark", String(localized: "Clear Shortcut", defaultValue: "Clear", bundle: .floe, comment: "Spoken for the button that removes a keyboard shortcut."), 7.5)
        case .empty: ("record.circle", String(localized: "Record", bundle: .floe, comment: "Spoken for the button that starts recording a keyboard shortcut."), 5.5)
        }
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .padding(inset)
            .accessibilityLabel(description)
    }
}

@Observable
private final class KeyCapture {
    /// Whether key presses are currently being intercepted.
    private(set) var isListening = false

    /// Whether to warn that the combination just typed belongs to the system.
    var isShowingReservedWarning = false

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onRecordingChange: (Bool) -> Void = { _ in
        // Set by start.
    }

    @ObservationIgnored private var onCapture: (KeyCombination) -> Void = { _ in
        // Set by start.
    }

    /// Begins intercepting key presses. Global hotkeys stand down for the duration,
    /// so the combination being replaced cannot fire while the replacement is typed.
    func start(onRecordingChange: @escaping (Bool) -> Void, onCapture: @escaping (KeyCombination) -> Void) {
        guard !isListening else {
            return
        }
        self.onRecordingChange = onRecordingChange
        self.onCapture = onCapture
        // Swallow the event either way: while recording, key presses are input
        // to this control rather than to whatever has focus.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.consider(event)
            return nil
        }
        isListening = true
        onRecordingChange(true)
    }

    /// Stops intercepting key presses and puts the hotkeys back to work.
    func stop() {
        guard isListening else {
            return
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isListening = false
        onRecordingChange(false)
    }

    /// Works out what an intercepted key press means.
    ///
    /// A bare Escape backs out of the recording. Everything else needs a
    /// modifier that is not Shift, since a global hotkey on an unmodified key
    /// would swallow ordinary typing everywhere.
    private func consider(_ event: NSEvent) {
        let keyCombination = KeyCombination(event: event)

        guard !keyCombination.modifiers.isEmpty, keyCombination.modifiers != .shift else {
            if keyCombination.key == .escape {
                stop()
            } else {
                NSSound.beep()
            }
            return
        }

        guard !keyCombination.isSystemReserved else {
            stop()
            isShowingReservedWarning = true
            return
        }

        onCapture(keyCombination)
        stop()
    }
}

// MARK: - SegmentButtonStyle

/// The style shared by the recorder's two halves, which round off the outer
/// end of the control and leave the inner end square.
private struct SegmentButtonStyle: ButtonStyle {
    /// Half the control's height, so the outer ends are round like the capsule buttons.
    static let outerRadius: CGFloat = 12
    /// The end of the control a segment sits at.
    enum Side {
        case leading
        case trailing
    }

    var side: Side
    var isHighlighted: Bool

    private var outline: some InsettableShape {
        let r = Self.outerRadius
        let radii = switch side {
        case .leading: RectangleCornerRadii(topLeading: r, bottomLeading: r)
        case .trailing: RectangleCornerRadii(bottomTrailing: r, topTrailing: r)
        }
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        // Pressing inverts the highlight, so a highlighted segment reads as
        // pressed when it is released and vice versa.
        let isFilled = configuration.isPressed != isHighlighted
        let borderShape = outline
        borderShape
            .fill(isFilled ? .tertiary : .quaternary)
            .overlay {
                configuration.label
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .thawGlass(.control, in: borderShape)
            .contentShape([.interaction, .focusEffect], borderShape)
    }
}
