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
    /// Key presses, and the clicks that move the caret somewhere the typed keys were not.
    private static let eventsOfInterest: CGEventMask = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        .reduce(0) { $0 | CGEventMask(1) << $1.rawValue }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var following: AnyCancellable?
    private var keys = KeywordBuffer()
    private var lent: SnippetPasteboard.Loan?
    private var giveBackTimer: Timer?
    private var appSwitch: NSObjectProtocol?

    private init() {}

    /// Installs the key tap, or keeps trying while Accessibility is not granted.
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

    /// Takes the key tap away and ends the retries, so no key of another app reaches Floe.
    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        keys.clear()
        if let appSwitch {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitch)
            self.appSwitch = nil
        }
        giveBack()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Listening now starts and stops with the snippets, and a tap only disabled would stay registered each time.
            CFMachPortInvalidate(tap)
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
            eventsOfInterest: Self.eventsOfInterest,
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
        if appSwitch == nil {
            appSwitch = NSWorkspace.shared.notificationCenter.addMainObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil
            ) { [weak self] in
                self?.keys.clear()
            }
        }
    }

    /// Tries again every ten seconds. The timer calls straight in, with no task of its own, so a try can't
    /// run after `stop` has ended the timer.
    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledOnMain(withTimeInterval: 10, repeats: true) { [weak self] in
            self?.attemptTap()
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
        // A click may have moved the caret, so the keys typed before it are not next to it any more.
        guard type == .keyDown else {
            keys.clear()
            return
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.magicUserData {
            return
        }
        guard SnippetStore.shared.expansionEnabled else { return }
        // A password field must not leave half a keyword behind.
        if IsSecureEventInputEnabled() {
            keys.clear()
            return
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            keys.clear()
            return
        }
        var chars = [UniChar](repeating: 0, count: 4)
        let typed: String? = chars.withUnsafeMutableBufferPointer { pointer in
            var length = 0
            event.keyboardGetUnicodeString(maxStringLength: pointer.count, actualStringLength: &length, unicodeString: pointer.baseAddress)
            guard length > 0, let base = pointer.baseAddress else { return nil }
            return String(utf16CodeUnits: base, count: length)
        }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let key = KeywordBuffer.key(code: code, flags: event.flags, characters: typed), let text = keys.take(key) else { return }
        guard let match = Snippet.match(typed: text, in: SnippetStore.shared.snippets) else { return }
        keys.clear()
        // Before the lend, so a clipboard placeholder reads what the person copied.
        let expanded = SnippetStore.shared.expanded(match)
        delete(count: match.keyword.count)
        giveBackTimer?.invalidate()
        lent = SnippetPasteboard.lend(expanded, after: lent)
        // After the deletes land, or the paste arrives before them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { KeySimulation.paste() }
        // The app reads the pasteboard when Command-V arrives, which can be a moment after it was sent.
        giveBackTimer = Timer.scheduledOnMain(withTimeInterval: 0.5, repeats: false) { [weak self] in
            self?.giveBack()
        }
    }

    /// Puts back what the pasteboard held before the last expansion, unless something was copied since.
    private func giveBack() {
        giveBackTimer?.invalidate()
        giveBackTimer = nil
        if let lent {
            SnippetPasteboard.giveBack(lent)
        }
        lent = nil
    }

    private func delete(count: Int) {
        for _ in 0 ..< count {
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: KeywordBuffer.backspaceKeyCode, keyDown: keyDown)
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
    if let refcon, type == .keyDown || type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        Unmanaged<TextExpander>.fromOpaque(refcon).takeUnretainedValue().handleTap(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
