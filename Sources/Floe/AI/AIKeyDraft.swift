//
//  AIKeyDraft.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine

/// The API key as the AI page's field holds it, beside what the Keychain holds for the address. The Keychain is
/// read when the page appears and when the address changes, and written only when the field differs from it.
final class AIKeyDraft: ObservableObject {
    @Published var text: String
    /// What the Keychain holds for the address on screen, as far as this page knows.
    private var saved: String
    private let keys: AIKeys

    /// `stored` is the key to show without reading, which a snapshot passes.
    init(address: String, stored: String? = nil, keys: AIKeys = .keychain) {
        let key = stored ?? keys.key(for: address) ?? ""
        text = key
        saved = key
        self.keys = keys
    }

    /// Another address shows its own key or none.
    func show(address: String) {
        let key = keys.key(for: address) ?? ""
        saved = key
        text = key
    }

    /// Saves what the field holds for the address, unless the Keychain already holds it.
    func save(for address: String) {
        guard text != saved else { return }
        keys.save(text, for: address)
        saved = text
    }
}
