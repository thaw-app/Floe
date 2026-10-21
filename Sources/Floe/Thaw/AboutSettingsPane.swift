//
//  AboutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3. What's New and Credits open in ReadingWindow, since Floe's settings
//  are a process of their own without Thaw's window scenes. The "more" menu and the footer keep the
//  destinations Floe has, and the updates card shows only in a build that can update (see
//  UpdatesManager.isAvailable). Floe's Diagnostics section closes the page, and the page opens with
//  the header every Floe settings page has.

import AppKit
import SwiftUI
import ThawUI

/// What the About page shows, read from the bundle so a build stamps its own version and commit.
nonisolated enum AppInfo {
    static let displayName = "Floe"
    static let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    static let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let commitString = Bundle.main.object(forInfoDictionaryKey: "GitCommitSHA") as? String ?? "unknown"
    static let copyrightString = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    private static let links = Bundle.main.object(forInfoDictionaryKey: "FloeLinks") as? [String: String] ?? [:]

    /// A web link from Info.plist's FloeLinks; nil when run outside the app bundle (`swift run`).
    static func link(_ name: String) -> URL? {
        links[name].flatMap(URL.init(string:))
    }

    static var repositoryURL: URL? {
        link("repository")
    }

    /// The changelog as text, for the release notes reader, and as a page, for the browser.
    static let changelogURL = URL(string: "https://raw.githubusercontent.com/thaw-app/Floe/main/CHANGELOG.md")!
    static let changelogPageURL = URL(string: "https://github.com/thaw-app/Floe/blob/main/CHANGELOG.md")!

    static var issuesURL: URL? {
        repositoryURL?.appendingPathComponent("issues")
    }

    static var buildDescription: String {
        """
        \(displayName) \(versionString) (\(buildString))
        Commit: \(commitString)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }
}

/// The About page: who Floe is and which build this is, then one card for
/// updates, then news and help actions. Project links and copyright form a
/// quiet footer; Thaw and the community links sit in the actions' menu. The log
/// file's switch is on the Privacy page.
struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var updatesManager: UpdatesManager
    let settings: AppSettings

    private static let iconSize: CGFloat = 96

    /// Half the icon, so the name beside it does not outweigh it.
    private static let nameSize: CGFloat = 48

    @State private var applicationIcon = AboutSettingsPane.currentApplicationIcon()
    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var menuAnchor = MoreMenuAnchor()

    var body: some View {
        ScrollView {
            SettingsPageColumn {
                VStack(spacing: ThawSpacing.section) {
                    identity
                    if updatesManager.isAvailable {
                        updates
                    }
                    actions
                    footer
                }
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The sidebar's behind-window material, so About reads as one surface
        // with it. Other panes keep the window background for their forms.
        .background {
            BehindWindowMaterialBackground(material: .sidebar)
                .ignoresSafeArea()
        }
        .onChange(of: colorScheme, initial: true) {
            applicationIcon = Self.currentApplicationIcon()
        }
        .onDisappear { copyFeedbackTask?.cancel() }
    }

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: ThawSpacing.gutter) {
            VStack(spacing: ThawSpacing.base) {
                HStack(spacing: ThawSpacing.inset) {
                    Text(verbatim: AppInfo.displayName)
                        .font(.system(size: Self.nameSize, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Image(nsImage: applicationIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .accessibilityHidden(true)
                }
                Text("The open source launcher for macOS")
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            details
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Details

    /// One line, monospaced so it can be selected and pasted. The copy button beside
    /// it copies the full block a bug report asks for.
    private var details: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.row) {
            Text(verbatim: "\(AppInfo.versionString) (\(AppInfo.buildString)) · \(AppInfo.commitString)")
                .font(ThawType.detail)
                .monospaced()
                .foregroundStyle(ThawInk.supporting)
                .textSelection(.enabled)
                .accessibilityLabel("Version \(AppInfo.versionString), build \(AppInfo.buildString), commit \(AppInfo.commitString)")
            Button {
                copyVersionInfo()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .buttonStyle(.settingsGlass)
            .controlSize(.small)
            .help(didCopy ? "Copied" : "Copy the version, build and commit for a bug report")
            .accessibilityLabel(didCopy ? "Copied" : "Copy version information")
        }
    }

    // MARK: Actions

    private var actions: some View {
        ThawActionGroup {
            Button("What’s New") {
                ReadingWindow.releaseNotes.show()
            }
            Button("Report a Bug") {
                if let url = AppInfo.issuesURL {
                    openURL(url)
                }
            }
            // A plain button that pops the menu, so it takes the same style,
            // size and corner as its neighbours; a SwiftUI Menu does not.
            Button {
                showMoreMenu()
            } label: {
                // Inside a Text the symbol takes a line of text's height, so
                // the button matches its neighbours instead of sitting short.
                Text(Image(systemName: "ellipsis"))
            }
            .help("More about \(AppInfo.displayName)")
            .accessibilityLabel("More about \(AppInfo.displayName)")
            .background { MoreMenuAnchorView(anchor: menuAnchor) }
        }
        .buttonStyle(.thawGrouped)
    }

    private var footer: some View {
        VStack(spacing: ThawSpacing.inset) {
            HStack(spacing: ThawSpacing.inset) {
                if let url = AppInfo.repositoryURL {
                    Link(destination: url) {
                        Text("Source Code").underline()
                    }
                    footerSeparator
                }
                Button {
                    ReadingWindow.acknowledgements.show()
                } label: {
                    Text("Credits").underline()
                }
                if let url = AppInfo.link("sponsor") {
                    footerSeparator
                    Link(destination: url) {
                        Text("Support Floe").underline()
                    }
                }
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)

            Text(AppInfo.copyrightString)
        }
        .font(ThawType.footnote)
        .foregroundStyle(ThawInk.supporting)
        .multilineTextAlignment(.center)
    }

    private var footerSeparator: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }

    /// Pops the secondary destinations under the actions button, for both
    /// clicks and keyboard activation.
    private func showMoreMenu() {
        let menu = NSMenu()
        func item(_ title: String, _ symbol: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
            let entry = ClosureMenuItem(title: title, handler: handler)
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return entry
        }
        let openURL = openURL
        menu.addItem(item(String(localized: "Extensions Folder", bundle: .floe), "puzzlepiece.extension") {
            NSWorkspace.shared.activateFileViewerSelecting([Paths.extensions])
        })
        menu.addItem(item(String(localized: "Data Folder", bundle: .floe), "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([Paths.data])
        })
        menu.addItem(item(String(localized: "Raycast Extensions Folder", bundle: .floe), "folder.badge.gearshape") {
            NSWorkspace.shared.activateFileViewerSelecting([Paths.raycastExtensions])
        })
        menu.addItem(.separator())
        if let url = AppInfo.link("discord") {
            menu.addItem(item(String(localized: "Join the Discord", bundle: .floe), "bubble.left.and.bubble.right") { openURL(url) })
        }
        menu.addItem(item(String(localized: "Raycast Extension Store", bundle: .floe), "storefront") {
            if let url = AppInfo.link("raycastExtensions") {
                openURL(url)
            }
        })
        if let url = AppInfo.link("thaw") {
            menu.addItem(.separator())
            menu.addItem(item("Thaw", "snowflake") { openURL(url) })
        }
        guard let anchor = menuAnchor.view else { return }
        // The anchor's own coordinate system is not flipped, so minY is its
        // bottom edge and the menu opens just below the button.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    // MARK: Updates

    /// The choices are pills, short enough to sit beside their labels. The two
    /// Sparkle switches are one choice: downloading implies checking.
    private var updates: some View {
        VStack(spacing: 0) {
            updateRow(String(localized: "Update channel", bundle: .floe)) {
                ThawPillPicker(selection: $updatesManager.updateChannel, values: UpdateChannel.allCases, title: \.title)
                    .accessibilityLabel("Update channel")
            }
            Divider()
            updateRow(String(localized: "Automatic updates", bundle: .floe)) {
                ThawPillPicker(
                    selection: automaticUpdatesMode,
                    options: AutomaticUpdates.allCases.map { ThawPillPicker.Option($0, title: .verbatim($0.shortTitle), help: .verbatim($0.title)) }
                )
                .accessibilityLabel("Automatic updates")
            }
            Divider()
            updateRow(UpdateText.lastChecked(updatesManager.lastUpdateCheckDate), isSecondary: true) {
                Button("Check Now") {
                    updatesManager.checkForUpdates()
                }
                .buttonStyle(.settingsGlass)
                .disabled(!updatesManager.canCheckNow)
            }
        }
        .font(ThawType.detail)
        .background(.quinary, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
    }

    private func updateRow(
        _ label: String,
        isSecondary: Bool = false,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(isSecondary ? AnyShapeStyle(ThawInk.supporting) : AnyShapeStyle(.primary))
            Spacer(minLength: ThawSpacing.inset)
            control()
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.base)
    }

    private var automaticUpdatesMode: Binding<AutomaticUpdates> {
        Binding {
            AutomaticUpdates(
                checks: updatesManager.automaticallyChecksForUpdates,
                downloads: updatesManager.automaticallyDownloadsUpdates
            )
        } set: { mode in
            updatesManager.automaticallyChecksForUpdates = mode.checks
            updatesManager.automaticallyDownloadsUpdates = mode.downloads
        }
    }

    // MARK: Helpers

    static func currentApplicationIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        return (icon.copy() as? NSImage) ?? icon
    }

    private func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppInfo.buildDescription, forType: .string)

        copyFeedbackTask?.cancel()
        didCopy = true
        copyFeedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            didCopy = false
            copyFeedbackTask = nil
        }
    }
}

/// Holds the AppKit view behind the actions button so the menu can be
/// positioned against the button itself. A reference box keeps the
/// representable from writing SwiftUI state during a view update.
private final class MoreMenuAnchor {
    weak var view: NSView?
}

/// An empty view behind the actions button for NSMenu.popUp to position
/// against, including on keyboard activation.
private struct MoreMenuAnchorView: NSViewRepresentable {
    let anchor: MoreMenuAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        anchor.view = nsView
    }
}
