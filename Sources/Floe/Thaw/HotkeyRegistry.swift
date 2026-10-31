//
//  HotkeyRegistry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to the launcher: takes a KeyCombination directly instead of Thaw's Hotkey model,
//  handles key-down only, and drops diagnostics logging.

import Carbon.HIToolbox
import Cocoa
import Combine
import ThawUI

/// Global hotkeys through Carbon, which needs no Accessibility permission.
final class HotkeyRegistry {
    private final class Binding {
        let identifier: EventHotKeyID
        let carbonKeyCode: UInt32
        let carbonModifiers: UInt32
        let perform: () -> Void

        var carbonRef: EventHotKeyRef?

        init(identifier: EventHotKeyID, carbonKeyCode: UInt32, carbonModifiers: UInt32, perform: @escaping () -> Void) {
            self.identifier = identifier
            self.carbonKeyCode = carbonKeyCode
            self.carbonModifiers = carbonModifiers
            self.perform = perform
        }
    }

    private let signature = OSType(0x464C_4F45) // "FLOE"

    private var lastIdentifier: UInt32 = 0

    private var eventHandlerRef: EventHandlerRef?

    private var bindings = [UInt32: Binding]()

    private var cancellables = Set<AnyCancellable>()

    /// While suspended, every binding is released, so a recorder can capture any combination.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            if isSuspended {
                releaseAll()
            } else {
                reclaimAll()
            }
        }
    }

    /// Returns an identifier for `unregister`, or nil when the system or another app owns the combination.
    func register(_ keyCombination: KeyCombination, handler: @escaping () -> Void) -> UInt32? {
        guard installEventHandlerIfNeeded() == noErr else {
            return nil
        }

        lastIdentifier += 1
        let id = lastIdentifier
        let binding = Binding(
            identifier: EventHotKeyID(signature: signature, id: id),
            carbonKeyCode: UInt32(keyCombination.key.rawValue),
            carbonModifiers: UInt32(keyCombination.modifiers.carbonFlags),
            perform: handler
        )

        guard isSuspended || claim(binding) else {
            return nil
        }

        bindings[id] = binding
        return id
    }

    func unregister(_ id: UInt32) {
        guard let binding = bindings.removeValue(forKey: id) else {
            return
        }
        release(binding)
    }

    func unregisterAll() {
        releaseAll()
        bindings.removeAll()
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        observeMenuTracking()

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            let registry = Unmanaged<HotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            return registry.dispatch(event)
        }

        var hotKeyEvent = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &hotKeyEvent,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    /// Carbon hotkeys fire even while a menu is tracking, so stand down until it closes.
    private func observeMenuTracking() {
        guard cancellables.isEmpty else {
            return
        }

        let center = NotificationCenter.default
        let menuOpened = center.publisher(for: NSMenu.didBeginTrackingNotification).map { _ in true }
        let menuClosed = center.publisher(for: NSMenu.didEndTrackingNotification).map { _ in false }

        menuOpened
            .merge(with: menuClosed)
            .sink { [weak self] isTracking in
                guard let self, !isSuspended else {
                    return
                }
                if isTracking {
                    releaseAll()
                } else {
                    reclaimAll()
                }
            }
            .store(in: &cancellables)
    }

    @discardableResult
    private func claim(_ binding: Binding) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.carbonKeyCode,
            binding.carbonModifiers,
            binding.identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            return false
        }
        binding.carbonRef = hotKeyRef
        return true
    }

    private func release(_ binding: Binding) {
        guard let hotKeyRef = binding.carbonRef, UnregisterEventHotKey(hotKeyRef) == noErr else {
            return
        }
        binding.carbonRef = nil
    }

    private func releaseAll() {
        bindings.values.forEach(release)
    }

    private func reclaimAll() {
        for binding in bindings.values where binding.carbonRef == nil {
            claim(binding)
        }
    }

    private func dispatch(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr, identifier.signature == signature, let binding = bindings[identifier.id] else {
            return OSStatus(eventNotHandledErr)
        }
        binding.perform()
        return noErr
    }
}
