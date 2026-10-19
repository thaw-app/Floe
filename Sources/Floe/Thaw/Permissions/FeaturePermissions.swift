//
//  FeaturePermissions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
import SwiftUI
import UserNotifications

/// Screen Recording, the home folders and notifications: each switches on one feature, is asked for when that
/// feature is first used, and is offered up front in the welcome and in Settings.
enum FeaturePermissions {
    static var system: [Permission] {
        [screenRecording, folders, notifications]
    }

    private static func pane(_ name: String) -> URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)")
    }

    private static var screenRecording: Permission {
        Permission(
            key: "screenRecording",
            title: String(localized: "Screen Recording", bundle: .floe, comment: "The macOS permission named Screen Recording."),
            iconName: "rectangle.dashed.badge.record",
            iconColor: .red,
            details: [String(localized: "Copy Text from Screen reads the text or the QR code in the part of the screen you drag over.", bundle: .floe)],
            summary: String(localized: "Copy the text or QR code in part of the screen.", bundle: .floe, comment: "One line on a permission card in the welcome."),
            isRequired: false,
            settingsURL: pane("Privacy_ScreenCapture"),
            check: { CGPreflightScreenCaptureAccess() },
            request: { completion in
                // macOS shows its prompt once and answers before the user does.
                let granted = CGRequestScreenCaptureAccess()
                completion(granted, !granted)
            }
        )
    }

    /// The folders fast file search walks first. macOS asks for each one on its own.
    private nonisolated static let folderNames = ["Desktop", "Documents", "Downloads"]
    private static let foldersAskedKey = "permissions.folders.asked"
    /// A read waits while macOS's prompt is up, so the poll leaves the folders alone until the asking is done.
    private static var askingForFolders = false

    /// Reading one of these folders is what makes macOS ask, so nothing is read until the user has asked once.
    private static func foldersGranted() -> Bool {
        UserDefaults.standard.bool(forKey: foldersAskedKey) && !askingForFolders && foldersReadable()
    }

    private nonisolated static func foldersReadable() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return folderNames.allSatisfy { (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent($0), includingPropertiesForKeys: nil)) != nil }
    }

    private static var folders: Permission {
        Permission(
            key: "folders",
            title: String(localized: "Folders", bundle: .floe, comment: "The title of a permission: access to the Desktop, Documents and Downloads folders."),
            iconName: "folder",
            iconColor: .cyan,
            details: [String(localized: "Fast file search finds the files in Desktop, Documents and Downloads by name. macOS asks for each folder.", bundle: .floe)],
            summary: String(localized: "Desktop, Documents and Downloads, for fast file search. macOS asks per folder.", bundle: .floe, comment: "One line on a permission card in the welcome."),
            isRequired: false,
            settingsURL: pane("Privacy_FilesAndFolders"),
            check: foldersGranted,
            request: { completion in
                let firstTime = !UserDefaults.standard.bool(forKey: foldersAskedKey)
                UserDefaults.standard.set(true, forKey: foldersAskedKey)
                askingForFolders = true
                // The reads raise macOS's prompts, one folder at a time, off the main thread.
                Task {
                    let granted = await Task.detached { foldersReadable() }.value
                    askingForFolders = false
                    completion(granted, firstTime && !granted)
                }
            }
        )
    }

    private static var notifications: Permission {
        Permission(
            key: "notifications",
            title: String(localized: "Notifications", bundle: .floe, comment: "The macOS permission named Notifications."),
            iconName: "bell.badge",
            iconColor: .pink,
            details: [String(localized: "A timer posts a notification with a sound when it ends.", bundle: .floe)],
            summary: String(localized: "A timer tells you when it ends.", bundle: .floe, comment: "One line on a permission card in the welcome."),
            isRequired: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
            check: {
                TimerAlerts.refreshStatus()
                return [.authorized, .provisional].contains(TimerAlerts.status)
            },
            request: { completion in
                let prompts = TimerAlerts.status == .notDetermined
                Task {
                    let granted = await TimerAlerts.requestAccess()
                    TimerAlerts.refreshStatus()
                    completion(granted, prompts)
                }
            }
        )
    }
}
