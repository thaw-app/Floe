//
//  SettingsPageHeader.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Where a grouped form puts its first content, from the column's leading edge and from the bottom of
/// the titlebar; the pages that are not forms place theirs the same.
enum SettingsPageHeading {
    static let leadingMargin: CGFloat = 30
    static let topMargin: CGFloat = 20
}

/// A page's own controls, at the top right. In a grouped form it is a section header with no rows,
/// so the form draws no card behind it.
struct SettingsPageHeader<Accessory: View>: View {
    private let accessory: Accessory

    init(@ViewBuilder accessory: () -> Accessory) {
        self.accessory = accessory()
    }

    var body: some View {
        Section {
            EmptyView()
        } header: {
            HStack(alignment: .center, spacing: ThawSpacing.inset) {
                Spacer(minLength: 0)
                accessory
            }
            .lineLimit(1)
            .textCase(nil)
            .padding(.bottom, ThawSpacing.base)
        }
    }
}
