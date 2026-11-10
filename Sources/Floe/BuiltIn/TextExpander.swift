//
//  TextExpander.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices
import Carbon
import Combine

/// Expands snippet keywords typed in other apps. Watches keystrokes with a
/// listen-only event tap, then deletes the keyword and pastes the expansion.
@MainActor final class TextExpander {
    static let shared = TextExpander()

    /// Marks events this expander posts itself, so they are never treated as typed input.
    private static let magicUserData: Int64 = 0x466C_6F65
    private static let maxBufferLength = 32
    private static let deleteKeyCode: CGKeyCode = 51

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var following: AnyCancellable?
    private var buffer = ""

    /// Keycodes that end a word rather than extend it.
    private static let resetKeyCodes: Set<CGKeyCode> = [
        36, // Return
        48, // Tab
        53, // Escape
        123, 124, 125, 126, // Arrow keys
    ]

    private init() {}

    func start() {
        guard tap == nil else { return }
        attemptTap()
    }

    /// Listens while a snippet could expand, and stops when the last keyword goes or expansion is switched off.
    func follow(_ store: SnippetStore) {
        following = store.$snippets.combineLatest(store.$expansionEnabled)
            .map { Snippet.canExpand($0, enabled: $1) }
            .removeDuplicates()
            .sink { [weak self] listens in
                if listens {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        buffer = ""
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func attemptTap() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: tapCallback,
            userInfo: refcon
        ) else {
            // No Accessibility yet, or the tap is busy. Try again later.
            scheduleRetry()
            return
        }
        retryTimer?.invalidate()
        retryTimer = nil
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.attemptTap() }
        }
        // Lets the system fire this with its other timers.
        retryTimer?.tolerance = 2
    }

    /// Re-enables the tap after the system disables it for timeout or heavy input.
    func reenable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    nonisolated func handleTap(type: CGEventType, event: CGEvent) {
        // Safe: the tap's source is on the main run loop, so this is the main thread and the event never leaves it.
        nonisolated(unsafe) let event = event
        MainActor.assumeIsolated {
            handle(type: type, event: event)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard type == .keyDown else { return }
        if event.getIntegerValueField(.eventSourceUserData) == Self.magicUserData {
            return
        }
        guard SnippetStore.shared.expansionEnabled else { return }
        if IsSecureEventInputEnabled() {
            return
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            buffer = ""
            return
        }
        // Modifier shortcuts act on the app, they are not typed text.
        if !event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) {
            buffer = ""
            return
        }
        if Self.resetKeyCodes.contains(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))) {
            buffer = ""
            return
        }
        var chars = [UniChar](repeating: 0, count: 4)
        let typed: String? = chars.withUnsafeMutableBufferPointer { pointer in
            var length = 0
            event.keyboardGetUnicodeString(maxStringLength: pointer.count, actualStringLength: &length, unicodeString: pointer.baseAddress)
            guard length > 0, let base = pointer.baseAddress else { return nil }
            return String(utf16CodeUnits: base, count: length)
        }
        guard let typed, !typed.isEmpty else { return }
        buffer.append(typed)
        if buffer.count > Self.maxBufferLength {
            buffer = String(buffer.suffix(Self.maxBufferLength))
        }
        guard let match = Snippet.match(typed: buffer, in: SnippetStore.shared.snippets) else { return }
        buffer = ""
        let expanded = SnippetStore.shared.expanded(match)
        delete(count: match.keyword.count)
        PasteboardContent.write(text: expanded, html: nil, file: nil)
        // After the deletes land, or the paste arrives before them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { KeySimulation.paste() }
    }

    private func delete(count: Int) {
        for _ in 0 ..< count {
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: Self.deleteKeyCode, keyDown: keyDown)
                event?.setIntegerValueField(.eventSourceUserData, value: Self.magicUserData)
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}

private nonisolated func tapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let refcon {
        let expander = Unmanaged<TextExpander>.fromOpaque(refcon).takeUnretainedValue()
        // Safe: the tap's source is on the main run loop.
        MainActor.assumeIsolated { expander.reenable() }
    }
    if let refcon, type == .keyDown {
        Unmanaged<TextExpander>.fromOpaque(refcon).takeUnretainedValue().handleTap(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
