//
//  SettingsSyncService.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import Foundation
import Security

/// Floe's side of settings sync: what the engine reads and writes here, and when it looks.
/// It runs in the launcher, the process that stays; Settings only shows what it reports.
final class SettingsSyncService {
    let engine: SyncEngine
    private let settings: AppSettings
    private let snippets: SnippetStore
    private let quicklinks: QuicklinkStore
    private let preferenceEdits = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AppSettings = .shared,
        snippets: SnippetStore = .shared,
        quicklinks: QuicklinkStore = .shared,
        extensions: ExtensionSettingsSync? = nil,
        storage: SyncJournalStorage = .file(Paths.support.appendingPathComponent("Sync.json")),
        availability: SyncAvailability = .system,
        makeStore: @escaping () -> any SyncStore = { UbiquitousSyncStore() },
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.snippets = snippets
        self.quicklinks = quicklinks
        let client = SyncClient(
            snapshot: {
                Self.snapshot(settings: settings, snippets: snippets, quicklinks: quicklinks)
                    .merging(extensions?.records() ?? [:]) { first, _ in first }
            },
            defaults: Self.freshRecords(),
            apply: { changed, removed in
                Self.apply(changed, removed: removed, settings: settings, snippets: snippets, quicklinks: quicklinks)
                    .union(extensions?.apply(changed, removed: removed) ?? [])
            },
            turnOff: { settings.syncsWithICloud = false }
        )
        engine = SyncEngine(client: client, storage: storage, availability: availability, makeStore: makeStore, now: now)
    }

    /// Follows the switch and every change from here on. `report` hears the status now and whenever it changes.
    func start(report: @escaping (SyncStatus) -> Void) {
        let engine = engine
        engine.onStatusChange = report
        settings.$syncsWithICloud.removeDuplicates()
            // After the publisher's willSet, so the engine reads settings that hold the new value.
            .receive(on: DispatchQueue.main)
            .sink { engine.setOn($0) }
            .store(in: &cancellables)
        // A second is long enough to gather a burst of edits and short enough that quitting rarely loses one.
        settings.objectWillChange.merge(with: snippets.objectWillChange, quicklinks.objectWillChange, preferenceEdits)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { engine.localChanged() }
            .store(in: &cancellables)
    }

    /// Call when an extension's preferences were saved, or the installed extensions changed. The engine looks soon after.
    func extensionSettingsChanged() {
        preferenceEdits.send()
    }

    private static func object(_ data: Data?) -> [String: Any] {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    static func freshRecords() -> [String: String] {
        SettingsSync.records(of: object(AppSettings.freshStoredJSON()))
            .merging(ItemSync<Quicklink>.quicklinks.records(of: QuicklinkStore.defaults)) { first, _ in first }
            .merging(ItemSync<Snippet>.snippets.records(of: [])) { first, _ in first }
    }

    static func snapshot(settings: AppSettings, snippets: SnippetStore, quicklinks: QuicklinkStore) -> [String: String] {
        SettingsSync.records(of: object(try? settings.exportedJSON()))
            .merging(ItemSync<Snippet>.snippets.records(of: snippets.snippets)) { first, _ in first }
            .merging(ItemSync<Quicklink>.quicklinks.records(of: quicklinks.links)) { first, _ in first }
    }

    /// Each store is assigned only when it changed, so its save and its message to Settings happen once or not at all.
    static func apply(_ changed: [String: String], removed: Set<String>, settings: AppSettings, snippets: SnippetStore, quicklinks: QuicklinkStore) -> Set<String> {
        var refused: Set<String> = []
        settings.takeStored { stored in
            let result = SettingsSync.applying(changed, removed: removed, to: stored)
            refused.formUnion(result.refused)
            return result.settings
        }
        let snippetResult = ItemSync<Snippet>.snippets.applying(changed, removed: removed, to: snippets.snippets)
        if snippetResult.items != snippets.snippets {
            snippets.snippets = snippetResult.items
        }
        let linkResult = ItemSync<Quicklink>.quicklinks.applying(changed, removed: removed, to: quicklinks.links)
        if linkResult.items != quicklinks.links {
            quicklinks.links = linkResult.items
        }
        return refused.union(snippetResult.refused).union(linkResult.refused)
    }
}

/// In the settings process, which runs no sync: what the launcher last said about its own.
final class SettingsSyncStatus: ObservableObject {
    static let shared = SettingsSyncStatus()

    @Published var status = SyncStatus()
}

/// What Settings says about sync, kept out of the views so it can be checked.
nonisolated enum SettingsSyncText {
    static func line(for status: SyncStatus) -> String {
        let state = switch status.state {
        case .off: String(localized: "Sync is off.", bundle: .floe)
        case .notSigned: String(localized: "Unavailable: this build of Floe is not signed for iCloud.", bundle: .floe)
        case .noAccount: String(localized: "Unavailable: this Mac is not signed in to iCloud.", bundle: .floe)
        case .syncing: String(localized: "Syncing…", bundle: .floe)
        case let .synced(date):
            String(localized: "Last synced \(date.formatted(date: .abbreviated, time: .shortened))", bundle: .floe, comment: "The placeholder is a date and a time.")
        case .full: String(localized: "Floe's space in iCloud is full. Changes made on this Mac are not uploaded.", bundle: .floe)
        }
        guard status.skipped > 0 else { return state }
        return state + " " + String(localized: "\(status.skipped) entries in iCloud could not be read and were skipped.", bundle: .floe, comment: "The placeholder is a count.")
    }

    /// The Privacy pane's row: what goes to iCloud, and what never does.
    static func privacyLine(isOn: Bool, includesExtensions: Bool, passwords: Bool = false) -> String {
        let neverSent = passwords
            ? String(localized: "Extension passwords and API keys are kept in iCloud Keychain. Clipboard history, receipts and what you search are never sent.", bundle: .floe)
            : String(localized: "Passwords, keys, clipboard history, receipts and what you search are never sent.", bundle: .floe)
        guard isOn else {
            return String(localized: "Settings sync is off, so nothing is kept in iCloud.", bundle: .floe) + " " + neverSent
        }
        let what = includesExtensions
            ? String(localized: "Aliases, hotkeys, favorites, hidden results, appearance, snippets, quicklinks and extension settings are kept in your iCloud account.", bundle: .floe)
            : String(localized: "Aliases, hotkeys, favorites, hidden results, appearance, snippets and quicklinks are kept in your iCloud account.", bundle: .floe)
        return what + " " + neverSent
    }

    /// The row under the password switch: where the passwords are, and why the last change failed if it did.
    static func passwordLine(for status: SecretSyncStatus) -> String {
        guard status.isAvailable else {
            return String(localized: "Unavailable: this build of Floe is not signed for iCloud Keychain.", bundle: .floe)
        }
        var line = String(localized: "Passwords stay on this Mac.", bundle: .floe)
        if status.isOn {
            line = status.kept == 0
                ? String(localized: "Passwords are kept in iCloud Keychain.", bundle: .floe)
                : String(localized: "\(status.kept) of your passwords could not be moved to iCloud Keychain and stay on this Mac.", bundle: .floe, comment: "The placeholder is a count.")
        }
        guard let failure = status.failure else { return line }
        return line + " " + String(localized: "The last change failed: \(reason(for: failure))", bundle: .floe, comment: "The placeholder is the system's description of an error.")
    }

    static func reason(for failure: OSStatus) -> String {
        if failure == errSecMissingEntitlement {
            return String(localized: "this build of Floe may not use iCloud Keychain.", bundle: .floe)
        }
        return (SecCopyErrorMessageString(failure, nil) as String?) ?? String(localized: "error \(Int(failure)).", bundle: .floe, comment: "The placeholder is an error number.")
    }
}
