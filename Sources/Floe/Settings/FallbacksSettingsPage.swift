//
//  FallbacksSettingsPage.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The rows offered under the results of every search: which ones, and in what order.
struct FallbacksSettingsPage: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var quicklinks: QuicklinkStore

    var body: some View {
        let choices = Fallback.choices(quicklinks: quicklinks.links, commands: catalog.allCommands.filter(settings.isEnabled))
        let chosen = Fallback.chosen(settings.fallbacks, among: choices, quicklinks: quicklinks.links)
        let available = choices.filter { choice in !chosen.contains { $0.id == choice.id } }
        Form {
            SettingsPageHeader()
            ThawSection(
                header: { Text("Fallbacks") },
                content: {
                    if chosen.isEmpty {
                        Text("No fallbacks. Searches end with what they found.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(chosen) { choice in
                        HStack(spacing: ThawSpacing.row) {
                            FallbackLabel(row: choice.row)
                            Spacer()
                            Button { move(choice, by: -1, shown: chosen) } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(chosen.first?.id == choice.id)
                            .help("Move Up")
                            Button { move(choice, by: 1, shown: chosen) } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(chosen.last?.id == choice.id)
                            .help("Move Down")
                            Button { remove(choice) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .help("Remove")
                        }
                    }
                },
                footer: { Text("Offered under your results, in this order, with what you typed. Return opens the first when nothing else matches.") }
            )
            if !available.isEmpty {
                ThawSection(header: { Text("Add") }, content: {
                    ForEach(available) { choice in
                        HStack(spacing: ThawSpacing.row) {
                            FallbackLabel(row: choice.row)
                            Spacer()
                            Button { add(choice) } label: {
                                Image(systemName: "plus.circle")
                            }
                            .help("Add")
                        }
                    }
                })
            }
        }
        .formStyle(.grouped)
    }

    /// The order as it stands, written out the first time it changes.
    private var ids: [String] {
        settings.fallbacks ?? Fallback.order(chosen: nil, quicklinks: quicklinks.links).map(\.id)
    }

    private func move(_ choice: FallbackChoice, by offset: Int, shown: [FallbackChoice]) {
        settings.fallbacks = Fallback.moving(choice.id, by: offset, in: ids, shown: shown.map(\.id))
    }

    private func remove(_ choice: FallbackChoice) {
        settings.fallbacks = ids.filter { $0 != choice.id }
    }

    private func add(_ choice: FallbackChoice) {
        settings.fallbacks = ids + [choice.id]
    }
}

private struct FallbackLabel: View {
    let row: RootItem

    var body: some View {
        HStack(spacing: ThawSpacing.row) {
            RootIcon(item: row)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                Text(row.subtitle ?? row.kind)
                    .font(ThawType.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
