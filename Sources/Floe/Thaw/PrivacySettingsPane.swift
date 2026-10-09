//
//  PrivacySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3's Privacy pane: the notice, the permissions and the network list.
//  The network rows are Floe's own, since what it contacts is not what Thaw does, and Thaw's
//  capture inspector and connection status sections have nothing to describe here.
//  The search sources' switches, the switch that keeps AI on this Mac and the row about
//  follow-up questions are Floe's too.

import SwiftUI
import ThawUI

/// What the app may see and where anything goes: the permissions it holds and the network calls it makes.
struct PrivacySettingsPane: View {
    @ObservedObject var settings: AppSettings
    var permissions: AppPermissions = .shared
    @State private var forgotSearches = false
    @State private var forgotReceipts = false

    var body: some View {
        Form {
            // Footer-only section: the one placement where a pill renders without the form's card around it.
            ThawSection {
                EmptyView()
            } footer: {
                SettingsWarningPill(
                    title: "No analytics",
                    message: "Floe collects no analytics or usage data. What you open, and how often, stays in a file on this Mac. The network calls it makes are listed below.",
                    systemImage: "hand.raised.fill",
                    tint: .green
                )
            }
            ThawSection("Permissions") {
                ForEach(permissions.allPermissions) { permission in
                    LabeledContent {
                        PermissionStatusControl(permission: permission)
                    } label: {
                        PermissionLabel(permission: permission)
                        Text(verbatim: permission.details.joined(separator: " "))
                    }
                }
            }
            ThawSection("Search Sources") {
                ForEach(SearchSourceInfo.switches) { source in
                    Toggle(isOn: isOn(source)) {
                        Text(source.title)
                        Text(source.detail)
                    }
                }
                row("SSH Hosts", String(localized: "Floe reads the host names in your SSH configuration to find them in the search, and connects by handing the name to your terminal.", bundle: .floe))
            }
            ThawSection("Shell Commands") {
                row("Commands", String(localized: "A search that starts with the prefix runs as a command in your shell, with everything your account may do. Nothing asks first.", bundle: .floe))
                row("Shell history", String(localized: "While a command is typed, the end of your shell’s history file is read to suggest earlier commands. Nothing from it is copied or kept.", bundle: .floe))
                row("Processes", String(localized: "“kill” and a name, or “port” and a number, lists your running processes. The list is read when you ask and is not kept.", bundle: .floe))
                Toggle(isOn: Binding(
                    get: { settings.recordsExtensionAccess },
                    set: { settings.setRecordsExtensionAccess($0) }
                )) {
                    Text("Record what extensions reach")
                    Text("Floe records the hosts an extension contacts, the folders it reads and changes and the programs it starts, as far as its runtime sees them. Each extension’s page in Settings shows its record and forgets it. The record stays on this Mac. Switching this off forgets every record, and nothing more is kept, also of an extension that is running now.")
                }
                row("GitHub and GitLab sign-in", String(localized: "An extension that signs in to GitHub or GitLab can be lent the sign-in of the GitHub CLI or the GitLab CLI on this Mac. Floe asks once for each extension, and for GitHub it names what that sign-in may do. The extension’s page in Settings takes it back. The token goes to that extension and nowhere else.", bundle: .floe))
                row("Finder", String(localized: "Running a command in Finder’s folder asks Finder which folder is in front, which macOS lets you allow or refuse.", bundle: .floe))
            }
            ThawSection("Search History") {
                Toggle(isOn: Binding(
                    get: { settings.remembersSearches },
                    set: { remembers in
                        settings.remembersSearches = remembers
                        if !remembers {
                            UsageStore.shared.forgetQueries()
                        }
                    }
                )) {
                    Text("Remember searches")
                    Text("The last 50 searches that opened something are kept on this Mac, and the Up arrow in an empty search brings them back. Switching this off forgets them.")
                }
                LabeledContent("Remembered searches") {
                    Button("Forget Them") {
                        UsageStore.shared.forgetQueries()
                        forgotSearches = true
                    }
                    .disabled(!settings.remembersSearches || forgotSearches)
                }
            }
            ThawSection("Reminders and Events") {
                row("Reminders", String(localized: "“remind” and a sentence adds one reminder to Reminders, due when the sentence says. It goes to your default list, or to the list the sentence ends with, as in “in Work”. macOS asks first whether Floe may use Reminders. After that Floe reads the names of your lists, and none of the reminders in them.", bundle: .floe))
                row("Calendar events", String(localized: "“event” and a sentence adds one event to your default calendar, starting when the sentence says. This uses the same full access to Calendar that showing your upcoming events does, and macOS asks first. The event’s receipt deletes it again.", bundle: .floe))
            }
            ThawSection("Contacts") {
                row("People", String(localized: "“contact” and a name finds people in your Contacts and shows a phone number or an email address beside each. macOS asks first whether Floe may read them, and only once you type that word and a name. The names are held in memory for a minute and are not saved.", bundle: .floe))
            }
            ThawSection("Receipts") {
                Toggle(isOn: Binding(
                    get: { settings.keepsReceipts },
                    set: { keeps in
                        settings.keepsReceipts = keeps
                        if !keeps {
                            ReceiptStore.shared.forget()
                        }
                    }
                )) {
                    Text("Keep receipts")
                    Text("The last 200 things Floe did that changed your Mac: commands it ran, files it moved to the Trash, processes it quit. Type “receipts” in the launcher to see them and to put a file back. They stay on this Mac. Switching this off forgets them.")
                }
                LabeledContent("Receipts kept") {
                    Button("Forget Them") {
                        ReceiptStore.shared.forget()
                        forgotReceipts = true
                    }
                    .disabled(!settings.keepsReceipts || forgotReceipts)
                }
            }
            ThawSection("Network Access") {
                if let host = PrivacyNetwork.updateHost {
                    AutomaticUpdateCheckToggle()
                    row("Updates", String(localized: "Checking asks \(host) whether a newer version exists. Floe asked before it started doing this.", bundle: .floe, comment: "The placeholder is the address of a server."))
                }
                row("Extension Store", String(localized: "Opening the Extension Store lists extensions from GitHub. Installing or updating one downloads it from GitHub and its packages from the npm registry.", bundle: .floe))
                row("AI", PrivacyNetwork.aiLine(source: settings.aiSource, baseURL: settings.aiBaseURL, tool: AskAI.configuredTool(settings), onThisMacOnly: settings.aiOnThisMacOnly))
                row("Follow-up questions", String(localized: "A follow-up in Ask AI sends the earlier questions and answers of that conversation again, to the same place. Floe keeps them in memory until the answer view closes and saves none of it.", bundle: .floe, comment: "Ask AI is the name of the feature that answers a question in the launcher."))
                Toggle(isOn: $settings.fetchesExchangeRates) {
                    Text("Download exchange rates")
                    Text(PrivacyNetwork.exchangeRatesLine(held: ExchangeRateStore.load()?.date))
                }
                Toggle(isOn: $settings.aiOnThisMacOnly) {
                    Text("Only use AI that runs on this Mac")
                    Text("A source that sends questions elsewhere is refused, for Ask AI and for extensions. Nothing else is asked in its place.")
                }
                row("Release notes", String(localized: "Opening What’s New from About reads Floe’s changelog from GitHub and keeps the last copy.", bundle: .floe))
                row("Extensions", String(localized: "Each extension makes its own requests, and the images it shows are loaded from wherever it points.", bundle: .floe))
            }
        }
        .formStyle(.grouped)
        // The grant happens in System Settings; look again whenever this page comes back.
        .onAppear { permissions.refreshPermissionsState() }
    }

    /// A source's switch: on while its id is among the settings' search sources.
    private func isOn(_ source: SearchSourceInfo) -> Binding<Bool> {
        Binding {
            settings.searchSources.contains(source.id)
        } set: { isOn in
            if isOn {
                settings.searchSources.insert(source.id)
            } else {
                settings.searchSources.remove(source.id)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.callout).foregroundStyle(ThawInk.supporting)
        }
    }
}

extension PrivacyNetwork {
    /// What the switch for exchange rates says: what is asked of whom and how often, and the day of the rates held.
    static func exchangeRatesLine(held date: String?) -> String {
        let what = String(localized: "The calculator converts money with the European Central Bank’s daily rates. Floe downloads the bank’s public file when the rates it holds are half a day old, and sends nothing about you or what you typed. Off, nothing is asked for and the rates are removed.", bundle: .floe)
        guard let date else { return what }
        return what + " " + String(localized: "Floe holds the rates of \(date).", bundle: .floe, comment: "The placeholder is a date as the bank writes it, such as 2026-10-07.")
    }
}

/// What the Privacy pane says about the network, kept out of the view so it can be checked.
enum PrivacyNetwork {
    /// Where update checks go; nil in a build that has no updates, which then says nothing about them.
    static var updateHost: String? {
        let configuration = UpdateConfiguration(info: Bundle.main.infoDictionary)
        guard configuration.hasUsableFeed else { return nil }
        return URL(string: configuration.feedURL)?.host
    }

    /// Where a question goes, for the source chosen in General; `tool` is the command line tool that would answer, if any.
    /// With `onThisMacOnly`, a source that is not on this Mac is said to be refused.
    static func aiLine(source: AISource, baseURL: String, tool: String? = nil, onThisMacOnly: Bool = false) -> String {
        switch source {
        case .tools where onThisMacOnly:
            guard let tool else {
                return String(localized: "A command line tool is chosen, which sends questions to the service it is signed in to. While the switch below is on, Floe refuses to ask it, so no question is sent.", bundle: .floe)
            }
            return String(localized: "The \(tool) tool is chosen, which sends questions to the service it is signed in to. While the switch below is on, Floe refuses to ask it, so no question is sent.", bundle: .floe, comment: "The placeholder is the name of a command line tool.")
        case .tools:
            guard let tool else { return String(localized: "The command line tool set in General is not installed, so no question is sent.", bundle: .floe) }
            return String(localized: "Questions go to the \(tool) tool, which sends them to the service it is signed in to, on your account there.", bundle: .floe, comment: "The placeholder is the name of a command line tool.")
        case .appleIntelligence:
            return String(localized: "Questions are answered by Apple Intelligence on this Mac. Nothing is sent anywhere.", bundle: .floe)
        case .api:
            let url = AIEndpoint.chatURL(baseURL: baseURL)
            guard let host = url?.host else { return String(localized: "Questions go to the address set in General, once it is filled in.", bundle: .floe) }
            let isOnThisMac = AIEndpoint.isOnThisMac(url)
            if onThisMacOnly, !isOnThisMac {
                return String(localized: "\(host) is chosen, which is not on this Mac. While the switch below is on, Floe refuses to ask it, so no question is sent.", bundle: .floe, comment: "The placeholder is the address of a server.")
            }
            return isOnThisMac
                ? String(localized: "Questions go to the server on this Mac at \(host). Nothing leaves the machine.", bundle: .floe, comment: "The placeholder is the address of a server.")
                : String(localized: "Questions go to \(host), with your key, and nowhere else.", bundle: .floe, comment: "The placeholder is the address of a server.")
        }
    }
}
