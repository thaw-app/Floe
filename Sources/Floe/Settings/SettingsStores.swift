//
//  SettingsStores.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import Foundation

/// The stores the settings views read and change. The settings process makes one, and each page is handed
/// the stores it uses.
struct SettingsStores {
    let settings: AppSettings
    let usage: UsageStore
    let receipts: ReceiptStore
    let quicklinks: QuicklinkStore
    let snippets: SnippetStore
    let extensions: ExtensionStore
    let extensionAccess: ExtensionAccessStore
    let permissions: AppPermissions
    let fileIndex: FileIndexStatus
    let sync: SettingsSyncStatus
    let appearance: ThawAppearanceFollower
    let updates: UpdatesManager
    /// Opens the welcome window again.
    var showWelcome: () -> Void = { /* no welcome window */ }
}

/// In the settings process, which holds no index: what the launcher last said about its own.
final class FileIndexStatus: ObservableObject {
    static let shared = FileIndexStatus()

    @Published var state: FileIndexService.State?
}
