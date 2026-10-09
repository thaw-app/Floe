//
//  SystemCommands.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Subprocess
import System

enum SystemCommand: String, CaseIterable, Identifiable {
    case lockScreen
    case sleep
    case sleepDisplays
    case restart
    case shutDown
    case logOut
    case emptyTrash
    case toggleAppearance
    case toggleWiFi
    case toggleMute
    case volumeUp
    case volumeDown
    case toggleBluetooth
    case ejectDisks
    case toggleKeepAwake
    case hideOtherApps
    case quitAllApps
    case playPause
    case nextTrack
    case previousTrack
    case nowPlaying

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .lockScreen: return String(localized: "Lock Screen", bundle: .floe, comment: "A command that locks the screen.")
        case .sleep: return String(localized: "Sleep", bundle: .floe, comment: "A command that puts the Mac to sleep.")
        case .sleepDisplays: return String(localized: "Sleep Displays", bundle: .floe, comment: "A command that turns the displays off.")
        case .restart: return String(localized: "Restart (system command)", defaultValue: "Restart", bundle: .floe, comment: "A command that restarts the Mac.")
        case .shutDown: return String(localized: "Shut Down", bundle: .floe, comment: "A command that turns the Mac off.")
        case .logOut: return String(localized: "Log Out", bundle: .floe, comment: "A command that logs the user out.")
        case .emptyTrash: return String(localized: "Empty Trash", bundle: .floe, comment: "A command that empties the Trash.")
        case .toggleAppearance: return String(localized: "Toggle Dark Mode", bundle: .floe, comment: "A command that switches between the light and the dark appearance.")
        case .toggleWiFi: return String(localized: "Toggle Wi-Fi", bundle: .floe, comment: "A command that turns Wi-Fi on or off.")
        case .toggleMute: return String(localized: "Toggle Mute", bundle: .floe, comment: "A command that turns the sound off or back on.")
        case .volumeUp: return String(localized: "Volume Up", bundle: .floe, comment: "A command that makes the sound louder.")
        case .volumeDown: return String(localized: "Volume Down", bundle: .floe, comment: "A command that makes the sound quieter.")
        case .toggleBluetooth: return String(localized: "Toggle Bluetooth", bundle: .floe, comment: "A command that turns Bluetooth on or off.")
        case .ejectDisks: return String(localized: "Eject All Disks", bundle: .floe, comment: "A command that ejects every external and network disk.")
        case .toggleKeepAwake: return String(localized: "Toggle Keep Awake", bundle: .floe, comment: "A command that stops the Mac from sleeping, or lets it sleep again.")
        case .hideOtherApps: return String(localized: "Hide Other Apps", bundle: .floe, comment: "A command that hides every app but the one in front.")
        case .quitAllApps: return String(localized: "Quit All Apps", bundle: .floe, comment: "A command that quits every open app.")
        case .playPause: return String(localized: "Play/Pause", bundle: .floe, comment: "A command that pauses the music, or plays it again.")
        case .nextTrack: return String(localized: "Next Track", bundle: .floe, comment: "A command that skips to the next song.")
        case .previousTrack: return String(localized: "Previous Track", bundle: .floe, comment: "A command that goes back to the song before.")
        case .nowPlaying: return String(localized: "Now Playing", bundle: .floe, comment: "A command that shows the song that is playing and its artist.")
        }
    }

    var symbol: String {
        switch self {
        case .lockScreen: return "lock"
        case .sleep: return "moon"
        case .sleepDisplays: return "display"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .emptyTrash: return "trash"
        case .toggleAppearance: return "circle.lefthalf.filled"
        case .toggleWiFi: return "wifi"
        case .toggleMute: return "speaker.slash"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .toggleBluetooth: return "dot.radiowaves.left.and.right"
        case .ejectDisks: return "eject"
        case .toggleKeepAwake: return "cup.and.saucer"
        case .hideOtherApps: return "eye.slash"
        case .quitAllApps: return "xmark.square"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        case .nowPlaying: return "music.note"
        }
    }

    var keywords: [String] {
        let words = switch self {
        case .lockScreen: String(localized: "lock, screen", bundle: .floe, comment: "Words that find the Lock Screen command, separated by commas.")
        case .sleep: String(localized: "sleep, rest", bundle: .floe, comment: "Words that find the Sleep command, separated by commas.")
        case .sleepDisplays: String(localized: "sleep, displays, screen off, monitor", bundle: .floe, comment: "Words that find the Sleep Displays command, separated by commas.")
        case .restart: String(localized: "restart, reboot", bundle: .floe, comment: "Words that find the Restart command, separated by commas.")
        case .shutDown: String(localized: "shut down, shutdown, power off, turn off", bundle: .floe, comment: "Words that find the Shut Down command, separated by commas.")
        case .logOut: String(localized: "log out, logout, sign out", bundle: .floe, comment: "Words that find the Log Out command, separated by commas.")
        case .emptyTrash: String(localized: "empty trash, trash, delete trash", bundle: .floe, comment: "Words that find the Empty Trash command, separated by commas.")
        case .toggleAppearance: String(localized: "dark mode, light mode, appearance, theme", bundle: .floe, comment: "Words that find the Toggle Dark Mode command, separated by commas.")
        case .toggleWiFi: String(localized: "wifi, wireless, airport, turn wi-fi off, turn wi-fi on", bundle: .floe, comment: "Words that find the Toggle Wi-Fi command, separated by commas.")
        case .toggleMute: String(localized: "mute, unmute, sound, volume, silence", bundle: .floe, comment: "Words that find the Toggle Mute command, separated by commas.")
        case .volumeUp: String(localized: "volume up, louder, sound, increase volume", bundle: .floe, comment: "Words that find the Volume Up command, separated by commas.")
        case .volumeDown: String(localized: "volume down, quieter, sound, decrease volume", bundle: .floe, comment: "Words that find the Volume Down command, separated by commas.")
        case .toggleBluetooth: String(localized: "bluetooth, turn bluetooth off, turn bluetooth on", bundle: .floe, comment: "Words that find the Toggle Bluetooth command, separated by commas.")
        case .ejectDisks: String(localized: "eject, unmount, disks, drives, volumes", bundle: .floe, comment: "Words that find the Eject All Disks command, separated by commas.")
        case .toggleKeepAwake: String(localized: "caffeinate, awake, prevent sleep, no sleep", bundle: .floe, comment: "Words that find the Toggle Keep Awake command, separated by commas.")
        case .hideOtherApps: String(localized: "hide, hide other apps, hide others", bundle: .floe, comment: "Words that find the Hide Other Apps command, separated by commas.")
        case .quitAllApps: String(localized: "quit all apps, quit all, close all apps", bundle: .floe, comment: "Words that find the Quit All Apps command, separated by commas.")
        case .playPause: String(localized: "play, pause, resume, stop music, music, spotify", bundle: .floe, comment: "Words that find the Play/Pause command, separated by commas.")
        case .nextTrack: String(localized: "next song, skip, skip song, music, spotify", bundle: .floe, comment: "Words that find the Next Track command, separated by commas.")
        case .previousTrack: String(localized: "previous, previous song, last song, go back, music, spotify", bundle: .floe, comment: "Words that find the Previous Track command, separated by commas.")
        case .nowPlaying: String(localized: "what's playing, what is playing, current song, song, track, music, spotify", bundle: .floe, comment: "Words that find the Now Playing command, separated by commas.")
        }
        return words.keywordList
    }

    var confirmation: String? {
        switch self {
        case .restart: return String(localized: "Restart your Mac now?", bundle: .floe)
        case .shutDown: return String(localized: "Shut down your Mac now?", bundle: .floe)
        case .logOut: return String(localized: "Log out now?", bundle: .floe)
        case .emptyTrash: return String(localized: "Empty the Trash? This can't be undone.", bundle: .floe)
        case .quitAllApps: return String(localized: "Quit all apps now?", bundle: .floe)
        default: return nil
        }
    }

    /// What a command that flips a setting does, which answers with the line for the HUD.
    var flip: (() -> String)? {
        switch self {
        case .toggleWiFi: SystemToggle.flipWiFi
        case .toggleMute: SystemToggle.flipMute
        case .volumeUp: { SystemToggle.stepVolume(by: SystemToggle.volumeStep) }
        case .volumeDown: { SystemToggle.stepVolume(by: -SystemToggle.volumeStep) }
        case .toggleBluetooth: SystemToggle.flipBluetooth
        case .ejectDisks: SystemToggle.ejectDisks
        case .toggleKeepAwake: SystemToggle.flipKeepAwake
        default: nil
        }
    }

    /// What the commands that go through System Events or Finder tell it.
    private var appleScript: String? {
        switch self {
        case .restart: #"tell application "System Events" to restart"#
        case .shutDown: #"tell application "System Events" to shut down"#
        case .logOut: #"tell application "System Events" to log out"#
        case .emptyTrash: #"tell application "Finder" to empty trash"#
        case .toggleAppearance: #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
        default: nil
        }
    }

    func perform() {
        if let appleScript {
            runAppleScript(appleScript)
            return
        }
        switch self {
        case .lockScreen:
            lockScreen()
        case .sleep:
            runPmset(arguments: ["sleepnow"])
        case .sleepDisplays:
            runPmset(arguments: ["displaysleepnow"])
        case .hideOtherApps:
            hideOtherApps()
        case .quitAllApps:
            quitAllApps()
        default:
            _ = flip?()
        }
    }

    private func lockScreen() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let sym = dlsym(handle, "SACLockScreenImmediate") else { return }
        typealias LockFn = @convention(c) () -> Void
        unsafeBitCast(sym, to: LockFn.self)()
    }

    private func runPmset(arguments: [String]) {
        Task {
            _ = try? await Subprocess.run(.path("/usr/bin/pmset"), arguments: Arguments(arguments), output: .discarded)
        }
    }

    private func runAppleScript(_ source: String) {
        AppleScript.execute(source, qos: .utility) { execution in
            guard execution.errorNumber != nil else { return }
            if execution.isRefused {
                Self.askForAutomation(toControl: String(localized: "System Events and Finder", bundle: .floe, comment: "The names of two apps, as they stand in a sentence that asks for permission to control them."))
            } else {
                let alert = NSAlert()
                alert.messageText = execution.errorMessage ?? String(localized: "The system command failed.", bundle: .floe)
                alert.runModal()
            }
        }
    }

    /// What to show when macOS refused a script (error -1743): the pane where it is allowed.
    static func askForAutomation(toControl apps: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Floe needs permission to control \(apps).", bundle: .floe, comment: "The placeholder is the name of an app, or of two.")
        alert.informativeText = String(localized: "Allow it in System Settings, Privacy and Security, Automation.", bundle: .floe)
        alert.addButton(withTitle: String(localized: "Open Settings (System Settings)", defaultValue: "Open Settings", bundle: .floe, comment: "A button that opens System Settings."))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .floe))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        {
            NSWorkspace.shared.openWithoutWaiting(url)
        }
    }

    private func hideOtherApps() {
        let workspace = NSWorkspace.shared
        let frontmostPID = workspace.frontmostApplication?.processIdentifier
        for app in workspace.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != frontmostPID
        {
            app.hide()
        }
    }

    private func quitAllApps() {
        let me = ProcessInfo.processInfo.processIdentifier
        let myself = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if app.processIdentifier == me {
                continue
            }
            if app.bundleIdentifier == "com.apple.finder" {
                continue
            }
            if let myself, app.bundleIdentifier == myself {
                continue
            }
            app.terminate()
        }
    }
}

nonisolated extension String {
    /// The words of a list written as one translated string, so a language may have more of them or fewer.
    var keywordList: [String] {
        split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
