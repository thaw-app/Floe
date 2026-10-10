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
//  UpdatesManager.isAvailable).

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
/// quiet footer.
struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @Bindable private var updatesManager = UpdatesManager.shared

    private static let iconSize: CGFloat = 96

    /// Half the icon, so the name beside it does not outweigh it.
    private static let nameSize: CGFloat = 48

    @State private var applicationIcon = AboutSettingsPane.currentApplicationIcon()
    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var menuAnchor = MoreMenuAnchor()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                identity
                if updatesManager.isAvailable {
                    updates
                }
                actions
                footer
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
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
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
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
                    .font(.callout)
                    .foregroundStyle(ThawInk.supporting)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            details
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Details

    /// Labels right-aligned against a shared edge, values in monospace so a
    /// hash and a build number line up and can be selected and pasted.
    private var details: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                detailRow("Version", value: AppInfo.versionString, isPrimary: true)
                detailRow("Build", value: AppInfo.buildString)
                detailRow("Commit", value: AppInfo.commitString)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            // Beside what it copies.
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

    private func detailRow(_ label: LocalizedStringKey, value: String, isPrimary: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(ThawInk.supporting)
                .gridColumnAlignment(.trailing)
            Text(verbatim: value)
                .monospaced()
                .fontWeight(isPrimary ? .medium : .regular)
                .foregroundStyle(isPrimary ? Color.primary : ThawInk.supporting)
                .textSelection(.enabled)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
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
        .buttonStyle(.settingsGlass)
        .controlSize(.regular)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
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
                if let url = AppInfo.link("thaw") {
                    footerSeparator
                    Link(destination: url) {
                        Text("Thaw").underline()
                    }
                }
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)

            Text(AppInfo.copyrightString)
        }
        .font(.footnote)
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
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Acknowledgements", bundle: .floe), "text.book.closed") { ReadingWindow.acknowledgements.show() })
        guard let anchor = menuAnchor.view else { return }
        // The anchor's own coordinate system is not flipped, so minY is its
        // bottom edge and the menu opens just below the button.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    // MARK: Updates

    /// Pickers are made borderless explicitly, since outside a Form they
    /// default to bordered. The two Sparkle switches are one picker:
    /// downloading implies checking.
    private var updates: some View {
        VStack(spacing: 0) {
            updateRow(String(localized: "Update channel", bundle: .floe)) {
                Picker("Update channel", selection: $updatesManager.updateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
            }
            Divider()
            updateRow(String(localized: "Automatic updates", bundle: .floe)) {
                Picker("Automatic updates", selection: automaticUpdatesMode) {
                    ForEach(AutomaticUpdates.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
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
        .font(.callout)
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
            Spacer(minLength: 12)
            control()
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private static func currentApplicationIcon() -> NSImage {
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

// MARK: - From Thaw's SettingsView and LayoutBarItemMenu

/// Behind-window vibrancy so surfaces sample the desktop rather than the
/// system-owned NavigationSplitView backdrop beneath the SwiftUI layer.
struct BehindWindowMaterialBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}

/// The system glass button, unmodified: its own padding and shape, so a
/// Settings button looks like one in System Settings and follows macOS as the
/// style changes. Kept as a name so call sites say what they mean.
extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var settingsGlass: GlassButtonStyle {
        .glass
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    /// AppKit's initializers are nonisolated, and so must be what stands in for them here.
    @available(*, unavailable)
    override nonisolated init(title _: String, action _: Selector?, keyEquivalent _: String) {
        fatalError("init(title:action:keyEquivalent:) has not been implemented")
    }

    @available(*, unavailable)
    required nonisolated init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}
