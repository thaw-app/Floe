//
//  MenuBarAppSetting.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Settings, Built-in Commands: whose actions the search lists, Thaw's or Punkto's, and whether that app is there.
struct MenuBarAppSetting: View {
    @ObservedObject var settings: AppSettings
    var thawURL: URL? = Thaw.applicationURL
    var punktoURL: URL? = Punkto.applicationURL

    private var app: MenuBarApp {
        MenuBarApp.resolved(chosen: settings.menuBarApp, thawIsInstalled: thawURL != nil, punktoIsInstalled: punktoURL != nil)
    }

    private var isInstalled: Bool {
        (app == .thaw ? thawURL : punktoURL) != nil
    }

    var body: some View {
        ThawPicker(selection: Binding(get: { app }, set: { settings.menuBarApp = $0 })) {
            ForEach(MenuBarApp.allCases) { app in
                Text(verbatim: app.name).tag(app)
            }
        } label: {
            Text("Thaw or Punkto", comment: "The setting that chooses between two apps, Thaw and Punkto, whose actions the search lists.")
            Text("The search lists the actions of this app. Punkto does nothing while Thaw is running.")
        }
        LabeledContent {
            if isInstalled {
                ThawBadge("Connected", tone: .tinted(.green))
            } else if app == .thaw, let link = AppInfo.link("thaw") {
                Link("Get Thaw", destination: link)
            }
        } label: {
            Text(verbatim: app.name)
            Text(Self.detail(for: app, isInstalled: isInstalled))
        }
    }

    static func detail(for app: MenuBarApp, isInstalled: Bool) -> String {
        switch (app, isInstalled) {
        case (.thaw, true):
            String(
                localized: "Thaw's actions are in the search: type “thaw” to see them. The ones that change a Thaw setting need Automation turned on in Thaw.",
                bundle: .floe,
                comment: "The word in quotation marks is typed as it is and stays in English."
            )
        case (.thaw, false):
            String(localized: "Install Thaw and its actions appear in the search.", bundle: .floe)
        case (.punkto, true):
            String(
                localized: "Punkto's actions are in the search: type “punkto” to see them.",
                bundle: .floe,
                comment: "Punkto is the name of an app. The word in quotation marks is typed as it is and stays in English."
            )
        case (.punkto, false):
            String(localized: "Install Punkto and its actions appear in the search.", bundle: .floe, comment: "Punkto is the name of an app.")
        }
    }
}
