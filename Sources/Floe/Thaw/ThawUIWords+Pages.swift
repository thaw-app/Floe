//
//  ThawUIWords+Pages.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

// MARK: - Updates

nonisolated extension UpdateChannel {
    /// The channels Floe publishes to. ThawUI's type also has Thaw's alpha channel, which Floe does not offer.
    static let floeChannels: [UpdateChannel] = [.stable, .beta]

    /// A channel Floe publishes to, so a stored or sent value it does not offer reads as unknown.
    init?(floeRawValue: String) {
        guard let channel = UpdateChannel(rawValue: floeRawValue), Self.floeChannels.contains(channel) else { return nil }
        self = channel
    }

    var title: String {
        switch self {
        case .stable: String(localized: "Stable", bundle: .floe, comment: "The update channel that only offers finished releases.")
        case .beta: String(localized: "Beta", bundle: .floe, comment: "The update channel that also offers test releases.")
        // Never shown: nothing offers it, and a stored value reads as Stable.
        case .alpha: rawValue
        }
    }

    /// The stored choice, falling back to Stable for a missing or unknown value.
    static func stored(in defaults: UserDefaults) -> UpdateChannel {
        defaults.string(forKey: defaultsKey).flatMap(UpdateChannel.init(floeRawValue:)) ?? .stable
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

nonisolated extension AutomaticUpdates {
    var title: String {
        switch self {
        case .off: String(localized: "Off", bundle: .floe, comment: "Automatic updates: never check.")
        case .check: String(localized: "Check only", bundle: .floe, comment: "Automatic updates: check, and do not download.")
        case .download: String(localized: "Check and download", bundle: .floe, comment: "Automatic updates: check, and download what is found.")
        }
    }

    /// The name in a pill, where the full one doesn't fit; the full one is its help.
    var shortTitle: String {
        switch self {
        case .off: title
        case .check: String(localized: "Check", bundle: .floe, comment: "Automatic updates, in a narrow pill: check, and do not download.")
        case .download: String(localized: "Download", bundle: .floe, comment: "Automatic updates, in a narrow pill: check, and download what is found.")
        }
    }
}

nonisolated extension UpdateConsentStrings {
    static let floe = UpdateConsentStrings(
        title: .floe("Keep \(AppInfo.displayName) up to date?"),
        message: .floe("\(AppInfo.displayName) can check for updates automatically. You can also check manually from the menu bar or Settings › About."),
        downloadAutomatically: .floe("Download and install updates automatically"),
        checkManually: .floe("Check Manually"),
        checkAutomatically: .floe("Check Automatically"),
        checkboxOn: LocalizedStringResource("On", bundle: .floe, comment: "What VoiceOver says for a checkbox that is on."),
        checkboxOff: LocalizedStringResource("Off", bundle: .floe, comment: "What VoiceOver says for a checkbox that is off.")
    )
}

extension View {
    /// Presents the consent sheet over the settings window while the manager asks for it.
    func updateConsentSheet(_ updatesManager: UpdatesManager) -> some View {
        modifier(UpdateConsentModifier(updatesManager: updatesManager))
    }
}

private struct UpdateConsentModifier: ViewModifier {
    @Bindable var updatesManager: UpdatesManager

    func body(content: Content) -> some View {
        content.updateConsentSheet(
            isPresented: $updatesManager.isConsentPresented,
            strings: .floe,
            onEnable: { autoDownload in
                updatesManager.answerConsent(autoDownload ? .download : .check)
            },
            onDisable: {
                updatesManager.answerConsent(.off)
            }
        )
    }
}

/// The General page's switch. Draws nothing in a build that cannot update.
struct AutomaticUpdateCheckToggle: View {
    @Bindable var updatesManager: UpdatesManager

    var body: some View {
        if updatesManager.isAvailable {
            Toggle("Automatically check for updates", isOn: $updatesManager.automaticallyChecksForUpdates)
        }
    }
}

// MARK: - What's New

nonisolated extension ThawAppInfo {
    /// Floe's name, version and links, for the release notes. Every release shows, on one list with no channels, and
    /// the fetched notes stay in the folder they have always been cached in.
    static let floe = ThawAppInfo(
        displayName: AppInfo.displayName,
        version: AppInfo.versionString,
        changelogURL: AppInfo.changelogURL,
        releasesURL: AppInfo.changelogPageURL,
        cacheFolderName: "org.thaw.floe",
        shownMajorVersion: nil,
        showsChannels: false
    )
}

nonisolated extension ChangelogDocument.Callout.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .note: .floe("Note")
        case .tip: .floe("Tip")
        case .important: .floe("Important")
        case .warning: .floe("Warning")
        case .caution: .floe("Caution")
        }
    }
}

nonisolated extension WhatsNewStrings {
    static let floe = WhatsNewStrings(
        title: .floe("What’s New"),
        releaseTitle: { version in
            version == "Unreleased" ? .floe("Not released yet") : .floe("What’s new in \(version)")
        },
        releaseSubtitle: { date, facts in Text("\(date) · \(facts)", bundle: .floe) },
        noRelease: { channel, appName in Text("There is no \(channel) release of \(appName) yet.", bundle: .floe) },
        loadFailed: { .floe("\($0) couldn’t load the release notes.") },
        fetchingOff: .floe("Fetching release notes is off."),
        fetchingOffCached: .floe("Fetching release notes is off, so this is the last copy fetched."),
        updateReady: .floe("This update is ready to install. Use the update window to install it now or later."),
        cachedCopy: .floe("The repository could not be reached, so this is the last copy fetched."),
        fullChangelog: .floe("Full changelog"),
        older: .floe("Older"),
        channelName: { .verbatim($0.title) },
        calloutName: { $0.title }
    )
}

// MARK: - About

nonisolated extension AboutStrings {
    static let floe = AboutStrings(
        tagline: .floe("The open source launcher for macOS"),
        versionLabel: { version, build, commit in .floe("Version \(version), build \(build), commit \(commit)") },
        copied: .floe("Copied"),
        copyHelp: .floe("Copy the version, build and commit for a bug report"),
        copyLabel: .floe("Copy version information"),
        whatsNew: .floe("What’s New"),
        reportBug: .floe("Report a Bug"),
        more: .floe("More about \(AppInfo.displayName)"),
        sourceCode: .floe("Source Code"),
        credits: .floe("Credits"),
        support: .floe("Support Floe")
    )
}

nonisolated extension AboutUpdateStrings {
    static let floe = AboutUpdateStrings(
        updateChannel: .floe("Update channel"),
        automaticUpdates: .floe("Automatic updates"),
        checkNow: .floe("Check Now"),
        notChecked: LocalizedStringResource("Not checked yet", bundle: .floe, comment: "Shown in place of the time updates were last checked."),
        lastChecked: { LocalizedStringResource("Last checked \($0)", bundle: .floe, comment: "The placeholder is a date and time.") },
        channelName: { .verbatim($0.title) },
        automaticUpdatesName: { .verbatim($0.title) },
        automaticUpdatesShortName: { .verbatim($0.shortTitle) }
    )
}

// MARK: - Acknowledgements

nonisolated extension AcknowledgementsStrings {
    static let floe = AcknowledgementsStrings(
        credits: .floe("Credits"),
        origins: LocalizedStringResource("Origins", bundle: .floe, comment: "The heading over the projects this app grew out of."),
        licenses: .floe("Licenses"),
        older: .floe("Older"),
        thanks: LocalizedStringResource(
            "Thank you to everyone who contributes code, documentation, and translations to \(AppInfo.displayName).",
            bundle: .floe,
            comment: "The placeholder is the name of this app."
        ),
        contributors: .floe("Contributors"),
        translators: .floe("Translators"),
        contribute: .floe("Contribute"),
        helpTranslate: .floe("Help translate")
    )
}

/// Where the credits page's two links go, as Thaw's do: the repository's contributors, and the translators in CREDITS.md.
nonisolated enum AcknowledgementLinks {
    static func contributors(repository: URL?) -> URL? {
        repository?.appending(path: "graphs/contributors")
    }

    static func translators(repository: URL?) -> URL? {
        repository?.appending(path: "blob/main/CREDITS.md")
    }
}

extension AcknowledgementsContent {
    /// Origins and Licenses come from `Credits`, which scripts/generate-credits.py writes. The credits page links to
    /// the repository's contributors and to the translators, naming nobody in the app.
    ///
    /// - Parameter link: Looks up a web link by its FloeLinks name; a test passes its own.
    static func floe(link: (String) -> URL? = AppInfo.link) -> AcknowledgementsContent {
        let repository = link("repository")
        return AcknowledgementsContent(
            contributeURL: repository,
            translateURL: link("translate"),
            contributorsURL: AcknowledgementLinks.contributors(repository: repository),
            translatorsURL: AcknowledgementLinks.translators(repository: repository),
            originsIntro: Text(String(
                localized: "\(AppInfo.displayName) is a sibling of Thaw, built by the same people in the same organization. It shares Thaw’s design system and much of its design.",
                bundle: .floe,
                comment: "The placeholder is the name of this app."
            )),
            origins: Credits.origins.map { credit in
                AcknowledgementEntry(name: Text(verbatim: credit.name), detail: Text(verbatim: credit.detail), url: link(credit.link))
            },
            licenses: .libraries(
                Credits.libraries.map { credit in
                    AcknowledgementEntry(name: Text(verbatim: credit.name), detail: Text(verbatim: credit.detail), url: link(credit.link))
                },
                note: Text(verbatim: Credits.trademark)
            )
        )
    }
}
