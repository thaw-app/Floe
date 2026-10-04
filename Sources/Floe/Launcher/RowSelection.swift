//
//  RowSelection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Which result is selected, told to that row alone: a move redraws the row left and the row reached, not the list.
final class RowSelection {
    final class Flag: ObservableObject {
        @Published var isOn = false
    }

    private var flags: [String: Flag] = [:]
    private(set) var selected: String?

    /// The flag a row watches. Made when the row first appears, already saying whether it is the selected one.
    func flag(for id: String) -> Flag {
        if let flag = flags[id] {
            return flag
        }
        let flag = Flag()
        flag.isOn = id == selected
        flags[id] = flag
        return flag
    }

    func select(_ id: String?) {
        guard id != selected else { return }
        if let selected {
            flags[selected]?.isOn = false
        }
        selected = id
        if let id {
            flags[id]?.isOn = true
        }
    }

    /// New results: the list is drawn again and every row asks for its flag anew.
    func reset() {
        flags.removeAll(keepingCapacity: true)
        selected = nil
    }
}

/// One result, drawn again only when its own selection changes.
struct SelectableRootRow: View {
    @ObservedObject var flag: RowSelection.Flag
    let model: LauncherModel
    let item: RootItem

    var body: some View {
        if case .calculator(let expression, let resultText, let errorText, let attributedResult) = item {
            CalculatorBlockView(
                expression: expression,
                result: resultText,
                attributedResult: attributedResult,
                error: errorText,
                selected: flag.isOn
            )
        } else {
            RootRow(model: model, item: item, selected: flag.isOn)
                .equatable()
        }
    }
}

/// The results. Equatable on what the rows show, which leaves the selection out: moving it does not walk the list.
struct RootResultList: View, Equatable {
    let model: LauncherModel
    let results: [RootResult]
    let version: Int
    let query: String
    let favorites: [String]
    let aliases: [String: String]
    let menuBarCommands: Set<String>

    init(model: LauncherModel, results: [RootResult]) {
        self.model = model
        self.results = results
        version = model.resultsVersion
        query = model.searchedQuery
        favorites = model.settings.favorites
        aliases = model.settings.aliases
        menuBarCommands = model.settings.menuBarCommands
    }

    static func == (lhs: RootResultList, rhs: RootResultList) -> Bool {
        lhs.version == rhs.version && lhs.query == rhs.query && lhs.favorites == rhs.favorites
            && lhs.aliases == rhs.aliases && lhs.menuBarCommands == rhs.menuBarCommands
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        // One view per result, title included: a lazy stack walks the whole list when rows vary in count.
                        VStack(alignment: .leading, spacing: 0) {
                            if let section = result.section, index == 0 || results[index - 1].section != section {
                                SectionTitle(title: section, isFirst: index == 0)
                            }
                            SelectableRootRow(flag: model.rowSelection.flag(for: result.id), model: model, item: result.item)
                                .onTapGesture { model.activate(result.item) }
                        }
                        .id(result.id)
                    }
                }
            }
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .background { SelectionFollower(model: model, results: results, proxy: proxy) }
        }
    }
}

/// Keeps the selected row in view. It watches the model so the list does not have to.
private struct SelectionFollower: View {
    @ObservedObject var model: LauncherModel
    let results: [RootResult]
    let proxy: ScrollViewProxy

    var body: some View {
        Color.clear
            .onChange(of: model.selection) {
                if results.indices.contains(model.selection) {
                    proxy.scrollTo(results[model.selection].id)
                }
            }
    }
}
