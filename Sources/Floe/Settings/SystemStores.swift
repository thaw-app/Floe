//
//  SystemStores.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import ServiceManagement

extension AppSettings {
    /// Login items only work for the installed app bundle, not `swift run`.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

/// Extension and command preference values. Plain values live in the extension's support folder
/// as preferences.json; password preferences live in the Keychain.
enum PreferenceStore {
    /// Called after stored values changed. The process link sets it, so the launcher's sync hears of edits made in Settings.
    static var onSaved: () -> Void = { /* nothing listens outside the app */ }

    static func directory(for extensionName: String) -> URL {
        Paths.data.appendingPathComponent(extensionName)
    }

    private static func storageKey(_ field: FieldSpec, command: ExtensionCommand?) -> String {
        PreferenceResolver.storageKey(field, commandName: command?.name)
    }

    private static func file(for extensionName: String) -> URL {
        directory(for: extensionName).appendingPathComponent("preferences.json")
    }

    /// An extension's plain stored values by storage key. Passwords are not among them.
    static func storedValues(_ extensionName: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: file(for: extensionName)) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The stored value for one field, without falling back to its default.
    static func value(_ field: FieldSpec, extensionName: String, command: ExtensionCommand?) -> Any? {
        let key = storageKey(field, command: command)
        if field.isSecret {
            return Keychain.read(account: "\(extensionName)/\(key)")
        }
        return storedValues(extensionName)[key]
    }

    static func save(_ values: [String: Any], fields: [FieldSpec], extensionName: String, command: ExtensionCommand?) {
        var stored = storedValues(extensionName)
        for field in fields {
            let key = storageKey(field, command: command)
            let value = values[field.name]
            if field.isSecret {
                let account = "\(extensionName)/\(key)"
                if let text = value as? String, !text.isEmpty {
                    Keychain.write(text, account: account)
                } else {
                    Keychain.delete(account: account)
                }
            } else {
                stored[key] = value
            }
        }
        try? FileManager.default.createDirectory(at: directory(for: extensionName), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: stored) {
            try? data.write(to: file(for: extensionName))
        }
        onSaved()
    }

    /// Every extension's plain stored values, for a settings export.
    static func allStoredValues() -> [String: [String: Any]] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.data.path)) ?? []
        return names.reduce(into: [:]) { result, name in
            let values = storedValues(name)
            if !values.isEmpty {
                result[name] = values
            }
        }
    }

    /// Adds imported values to an extension's stored ones; the imported value wins for a key in both.
    static func merge(_ values: [String: Any], extensionName: String) {
        let merged = storedValues(extensionName).merging(values) { _, imported in imported }
        try? FileManager.default.createDirectory(at: directory(for: extensionName), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: merged) {
            try? data.write(to: file(for: extensionName))
        }
        onSaved()
    }

    /// Password preference keys by extension, never their values.
    static func secretKeys(for commands: [ExtensionCommand]) -> [String: [String]] {
        commands.reduce(into: [:]) { result, command in
            let keys = command.extensionPreferences.filter(\.isSecret).map { PreferenceResolver.storageKey($0, commandName: nil) }
                + command.commandPreferences.filter(\.isSecret).map { PreferenceResolver.storageKey($0, commandName: command.name) }
            result[command.extensionName, default: []].append(contentsOf: keys.filter { !(result[command.extensionName] ?? []).contains($0) })
        }
        .filter { !$0.value.isEmpty }
    }

    /// Everything a command's `getPreferenceValues()` should return: stored values, then defaults.
    static func resolvedValues(for command: ExtensionCommand) -> [String: Any] {
        let values = PreferenceResolver.resolve(
            extensionFields: command.extensionPreferences,
            commandFields: command.commandPreferences,
            commandName: command.name,
            stored: storedValues(command.extensionName),
            secret: { Keychain.read(account: "\(command.extensionName)/\($0)") }
        )
        return AppPickerValue.resolve(values, fields: command.preferences, apps: InstalledApps.list)
    }

    static func missingRequired(for command: ExtensionCommand) -> [FieldSpec] {
        PreferenceResolver.missingRequired(command.preferences, values: resolvedValues(for: command))
    }
}

/// Applications in the usual folders, for app pickers.
enum InstalledApps {
    static func list() -> [AppPickerValue.App] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", "\(home)/Applications"]
        return folders.flatMap { folder -> [AppPickerValue.App] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            return names.filter { $0.hasSuffix(".app") }.map { name in
                let path = "\(folder)/\(name)"
                return AppPickerValue.App(name: (name as NSString).deletingPathExtension, path: path, bundleId: Bundle(path: path)?.bundleIdentifier)
            }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
