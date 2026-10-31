//
//  ThawSupportNotice.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Settings, General: whether Thaw is there to be asked, and where its actions are found.
struct ThawSupportNotice: View {
    var applicationURL: URL? = Thaw.applicationURL

    var body: some View {
        LabeledContent {
            if applicationURL != nil {
                ThawBadge("Connected", tone: .tinted(.green))
            } else if let link = AppInfo.link("thaw") {
                Link("Get Thaw", destination: link)
            }
        } label: {
            Text("Thaw")
            Text(Self.detail(isInstalled: applicationURL != nil))
        }
    }

    static func detail(isInstalled: Bool) -> String {
        isInstalled
            ? String(
                localized: "Thaw's actions are in the search: type “thaw” to see them. The ones that change a Thaw setting need Automation turned on in Thaw.",
                bundle: .floe,
                comment: "The word in quotation marks is typed as it is and stays in English."
            )
            : String(localized: "Install Thaw and its actions appear in the search.", bundle: .floe)
    }
}
