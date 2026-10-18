//
//  ViewState.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One line of the action menu: an action, or a submenu that opens more.
struct MenuEntry: Identifiable {
    let node: Node
    let section: String?
    var isSubmenu: Bool {
        node.type == "ActionPanel.Submenu"
    }

    var id: Int {
        node.id
    }
}

/// What the panel shows for a rendered tree: the top screen's view, its rows, actions and form values.
/// Pure functions of the tree, so the session only adds selection and process I/O.
enum ViewState {
    static func screen(in root: Node?) -> Node? {
        root?.children.last { $0.type == "_screen" }
    }

    static func view(in root: Node?) -> Node? {
        screen(in: root)?.content.first
    }

    static func isList(_ view: Node?) -> Bool {
        view?.type == "List" || view?.type == "Grid"
    }

    /// The list's items, flattened across sections and filtered by the search text when the list filters itself.
    static func rows(of view: Node?, searchText: String) -> [Row] {
        guard let view, isList(view) else { return [] }
        var rows: [Row] = []
        for child in view.content {
            if child.type.hasSuffix(".Section") {
                rows += child.content.filter { $0.type.hasSuffix(".Item") }.map { Row(node: $0, sectionTitle: child.string("title"), sectionID: child.id) }
            } else if child.type.hasSuffix(".Item") {
                rows.append(Row(node: child, sectionTitle: nil))
            }
        }
        let tokens = searchText.lowercased().split(separator: " ")
        guard filtersLocally(view), !tokens.isEmpty else { return rows }
        return rows.filter { row in
            let keywords = (row.node.props["keywords"] as? [String] ?? []).joined(separator: " ")
            let haystack = "\(row.node.string("title") ?? "") \(row.node.string("subtitle") ?? "") \(keywords)".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    /// Raycast filters a list itself unless the extension handles search text, or says otherwise with `filtering`.
    static func filtersLocally(_ view: Node) -> Bool {
        if let filtering = view.props["filtering"] as? Bool {
            return filtering
        }
        if view.props["filtering"] != nil {
            return true
        }
        return !view.handlers.contains("onSearchTextChange")
    }

    static func selectedRow(_ rows: [Row], selection: Int) -> Row? {
        rows.isEmpty ? nil : rows[max(0, min(selection, rows.count - 1))]
    }

    /// The action panel for what's selected: the row's, else the empty view's, else the view's own.
    static func actionPanel(view: Node?, selectedRow: Row?) -> Node? {
        guard let view else { return nil }
        guard isList(view) else { return view.slot("actions") }
        return selectedRow?.node.slot("actions")
            ?? view.content.first { $0.type == "EmptyView" }?.slot("actions")
            ?? view.slot("actions")
    }

    /// Every action, flattened; ↵ runs the first and ⌘↵ the second, as in Raycast.
    static func actions(in panel: Node?) -> [Node] {
        panel?.descendants(ofType: "Action") ?? []
    }

    /// What the action menu lists for a panel or an open submenu, with section titles; a query
    /// searches everything underneath, submenus included.
    static func menuEntries(in container: Node?, query: String) -> [MenuEntry] {
        guard let container else { return [] }
        if !query.isEmpty {
            let query = query.lowercased()
            return container.descendants(ofType: "Action")
                .filter { ($0.string("title") ?? "").lowercased().contains(query) }
                .map { MenuEntry(node: $0, section: nil) }
        }
        var entries: [MenuEntry] = []
        func collect(_ node: Node, section: String?) {
            for child in node.content {
                switch child.type {
                case "ActionPanel.Section": collect(child, section: child.string("title") ?? "")
                case "Action", "ActionPanel.Submenu": entries.append(MenuEntry(node: child, section: section))
                default: collect(child, section: section)
                }
            }
        }
        collect(container, section: nil)
        return entries
    }

    static func clamp(_ index: Int, count: Int) -> Int {
        max(0, min(index, count - 1))
    }

    // MARK: Forms

    static func formFields(of view: Node?) -> [Node] {
        guard let view, view.type == "Form" else { return [] }
        return view.content.filter { $0.props["id"] is String }
    }

    /// The field's current value: the extension's controlled `value`, else what was typed, else its default.
    static func formValue(_ field: Node, typed: [String: Any]) -> Any? {
        guard let id = field.props["id"] as? String else { return nil }
        if let value = field.props["value"] ?? typed[id] ?? field.props["defaultValue"] {
            return value
        }
        // Like Raycast, a dropdown with nothing chosen shows (and submits) its first item.
        if field.type == "Form.Dropdown" {
            return field.descendants(ofType: "Dropdown.Item").first?.props["value"]
        }
        return nil
    }

    /// Values keyed by field id, as Raycast hands them to onSubmit.
    static func submittedValues(of view: Node?, typed: [String: Any]) -> [String: Any] {
        var values: [String: Any] = [:]
        for field in formFields(of: view) {
            guard let id = field.props["id"] as? String else { continue }
            values[id] = wireValue(formValue(field, typed: typed) ?? emptyValue(for: field.type), field: field)
        }
        return values
    }

    static func emptyValue(for type: String) -> Any {
        switch type {
        case "Form.Checkbox": false
        case "Form.TagPicker", "Form.FilePicker": [String]()
        case "Form.DatePicker": NSNull()
        default: ""
        }
    }

    /// Dates cross the bridge tagged so the host can turn them back into Date objects.
    static func wireValue(_ value: Any, field: Node) -> Any {
        if field.type == "Form.DatePicker", let iso = value as? String {
            return ["$date": iso]
        }
        return value
    }
}
