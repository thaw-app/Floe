//
//  SettingsPageHeader.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The name of the page on show, set once by SettingsView for every page.
struct SettingsPageHeading: Equatable {
    var title = ""

    /// Where a grouped form puts its header, from the column's leading edge and from the bottom of
    /// the titlebar; the pages that are not forms place theirs the same.
    static let leadingMargin: CGFloat = 30
    static let topMargin: CGFloat = 20
}

extension EnvironmentValues {
    @Entry var settingsPageHeading = SettingsPageHeading()
}

/// The top of a settings page: its name in large bold type, and the page's own controls on the right. The window has no toolbar, so this is where a page is named,
/// and it scrolls away with the page.
///
/// In a grouped form it is a section header with no rows, so the form draws no card behind it.
struct SettingsPageHeader<Accessory: View>: View {
    @Environment(\.settingsPageHeading) private var heading
    private let accessory: Accessory

    /// Large enough to name the page at a glance, as the Mac's own settings windows do.
    private static var titleFont: Font {
        .title.bold()
    }

    init(@ViewBuilder accessory: () -> Accessory) {
        self.accessory = accessory()
    }

    var body: some View {
        Section {
            EmptyView()
        } header: {
            HStack(alignment: .center, spacing: ThawSpacing.inset) {
                Text(heading.title)
                    .font(Self.titleFont)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                accessory
            }
            .lineLimit(1)
            // The form's section headers are small and secondary; the page's name is neither.
            .textCase(nil)
            .padding(.bottom, ThawSpacing.base)
        }
    }
}

extension SettingsPageHeader where Accessory == EmptyView {
    init() {
        accessory = EmptyView()
    }
}
