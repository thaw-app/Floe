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
    func setLaunchAtLogin(_ wanted: Bool) {
        objectWillChange.send()
        if wanted {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}

/// One extension's preferences.json. A file that is there but cannot be read is never written over, so the values in
/// it are not replaced by the few a save brings.
nonisolated enum PreferenceFile {
    enum Contents {
        case missing
        case values([String: Any])
        case unreadable
    }

    static func read(_ file: URL) -> Contents {
        guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
        guard let data = try? Data(contentsOf: file),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .unreadable }
        return .values(values)
    }

    /// Writes the whole file or nothing. False when nothing was written.
    @discardableResult
    static func write(_ values: [String: Any], to file: URL) -> Bool {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    /// Reads, changes and writes back. A null value removes its key. False, and nothing written, when the file is
    /// there but could not be read or the write failed.
    @discardableResult
    static func update(_ file: URL, _ change: ([String: Any]) -> [String: Any]) -> Bool {
        let stored: [String: Any]
        switch read(file) {
        case .missing: stored = [:]
        case let .values(values): stored = values
        case .unreadable: return false
        }
        return write(change(stored).filter { !($0.value is NSNull) }, to: file)
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
        switch storedFile(extensionName) {
        case let .values(values): return values
        case .missing: return [:]
        case .unreadable:
            Log.extensions.error("\(extensionName)'s preferences.json could not be read, so it is left as it is")
            return [:]
        }
    }

    /// An extension's preferences.json, telling a missing file from one that could not be read.
    static func storedFile(_ extensionName: String) -> PreferenceFile.Contents {
        PreferenceFile.read(file(for: extensionName))
    }

    /// The stored value for one field, without falling back to its default.
    static func value(_ field: FieldSpec, extensionName: String, command: ExtensionCommand?) -> Any? {
        let key = storageKey(field, command: command)
        if field.isSecret {
            return Keychain.read(account: "\(extensionName)/\(key)")
        }
        return storedValues(extensionName)[key]
    }

    /// False when the plain values could not be written, the file left as it was.
    @discardableResult
    static func save(_ values: [String: Any], fields: [FieldSpec], extensionName: String, command: ExtensionCommand?) -> Bool {
        guard ExtensionCommand.isUsableName(extensionName) else { return false }
        // A field with no value is removed from the file, as a null.
        var plain: [String: Any] = [:]
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
                plain[key] = value ?? NSNull()
            }
        }
        let saved = PreferenceFile.update(file(for: extensionName)) { $0.merging(plain) { _, new in new } }
        return finish(saved, extensionName)
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
    /// A name no extension could have, such as one with a slash, is skipped, so nothing lands outside Floe's data folder.
    /// A null among the values removes its key. False when nothing was written.
    @discardableResult
    static func merge(_ values: [String: Any], extensionName: String) -> Bool {
        guard ExtensionCommand.isUsableName(extensionName) else { return false }
        let saved = PreferenceFile.update(file(for: extensionName)) { $0.merging(values) { _, imported in imported } }
        return finish(saved, extensionName)
    }

    private static func finish(_ saved: Bool, _ extensionName: String) -> Bool {
        if saved {
            onSaved()
        } else {
            Log.extensions.error("\(extensionName)'s preferences were not saved")
        }
        return saved
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
        // With nothing required there is nothing to read: no file, no Keychain, no list of apps.
        guard command.preferences.contains(where: \.required) else { return [] }
        return PreferenceResolver.missingRequired(command.preferences, values: resolvedValues(for: command))
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

    /// The app Raycast names for a quicklink: a path to an app, an app's name in the usual folders, or its bundle
    /// identifier. Nil when it is not on this Mac.
    static func choice(named name: String, among apps: @autoclosure () -> [AppPickerValue.App] = list()) -> AppChoice? {
        let path = name.hasPrefix("/")
            ? name
            : apps().first { $0.name == name || $0.bundleId == name }?.path ?? AppLookup.system.url(name)?.path
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return PreferredApps.choice(forAppAt: URL(fileURLWithPath: path), installed: .system)
    }
}
