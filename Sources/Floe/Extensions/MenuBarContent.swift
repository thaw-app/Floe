//
//  MenuBarContent.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What a menu-bar command's status button shows.
struct MenuBarStatusContent: Equatable {
    struct Changes: OptionSet {
        let rawValue: Int
        static let title = Changes(rawValue: 1)
        static let image = Changes(rawValue: 2)
        static let toolTip = Changes(rawValue: 4)
    }

    var title = ""
    var icon: MenuBarIcon?
    var toolTip: String?

    init(title: String = "", icon: MenuBarIcon? = nil, toolTip: String? = nil) {
        self.title = title
        self.icon = icon
        self.toolTip = toolTip
    }

    /// A render without a tooltip keeps the one before it, as the button always has.
    init(root: Node?, previous: MenuBarStatusContent?, icon: (Any?) -> MenuBarIcon?) {
        let extra = root?.menuBarExtra
        self.title = extra?.string("title") ?? ""
        self.icon = extra.flatMap { icon($0.props["icon"]) }
        self.toolTip = extra?.string("tooltip") ?? previous?.toolTip
    }

    /// The parts of the button to set. Setting one that did not change still redraws the menu bar.
    func changes(from previous: MenuBarStatusContent?) -> Changes {
        guard let previous else { return [.title, .image, .toolTip] }
        var changes: Changes = []
        if title != previous.title {
            changes.insert(.title)
        }
        if icon != previous.icon {
            changes.insert(.image)
        }
        if toolTip != previous.toolTip {
            changes.insert(.toolTip)
        }
        return changes
    }

    /// A button with neither a title nor an image would be invisible, so it shows the command's name.
    func shownTitle(hasImage: Bool, commandTitle: String) -> String {
        title.isEmpty && !hasImage ? commandTitle : title
    }
}

/// One row of a menu-bar command's menu.
struct MenuBarMenuItem: Equatable {
    /// What makes a row the same row in the next render: the node it came from, or its fixed place.
    enum Key: Hashable {
        case item(Int), header(Int), submenu(Int)
        case separator, loading, empty, failure, retry, remove
    }

    enum Role: Equatable {
        /// Sends `onAction` to the node with this id.
        case action(node: Int)
        case disabled, separator, header
        case submenu([MenuBarMenuItem])
        case retry, remove
    }

    let key: Key
    let role: Role
    var title = ""
    var subtitle: String?
    var toolTip: String?
    var icon: MenuBarIcon?
    var shortcut: Shortcuts.KeyEquivalent?

    static let separator = MenuBarMenuItem(key: .separator, role: .separator)

    /// The whole menu for one state of a session, ending with the row that takes the command out of the menu bar.
    static func items(root: Node?, failure: SessionFailure?, commandTitle: String, icon: (Any?) -> MenuBarIcon?) -> [MenuBarMenuItem] {
        var items: [MenuBarMenuItem] = []
        if let failure {
            items.append(MenuBarMenuItem(key: .failure, role: .disabled, title: failure.message))
            items.append(MenuBarMenuItem(key: .retry, role: .retry, title: String(localized: "Try Again", bundle: .floe)))
        } else if let extra = root?.menuBarExtra {
            let children = extra.content
            if extra.bool("isLoading"), children.isEmpty {
                items.append(MenuBarMenuItem(key: .loading, role: .disabled, title: String(localized: "Loading…", bundle: .floe)))
            } else {
                append(children, to: &items, icon: icon)
                if items.isEmpty {
                    items.append(MenuBarMenuItem(key: .empty, role: .disabled, title: commandTitle))
                }
            }
        } else {
            items.append(MenuBarMenuItem(key: .loading, role: .disabled, title: String(localized: "Loading…", bundle: .floe)))
        }
        // Always the last row, so an item can be taken out of the menu bar from the menu bar.
        items.append(.separator)
        items.append(MenuBarMenuItem(key: .remove, role: .remove, title: String(localized: "Remove from Menu Bar", bundle: .floe)))
        return items
    }

    private static func append(_ nodes: [Node], to items: inout [MenuBarMenuItem], icon: (Any?) -> MenuBarIcon?) {
        for node in nodes {
            switch node.type {
            case "MenuBarExtra.Item":
                let hasAction = node.handlers.contains("onAction")
                items.append(MenuBarMenuItem(
                    key: .item(node.id),
                    role: hasAction ? .action(node: node.id) : .disabled,
                    title: node.string("title") ?? "",
                    subtitle: node.string("subtitle"),
                    toolTip: node.string("tooltip"),
                    icon: icon(node.props["icon"]),
                    shortcut: Shortcuts.keyEquivalent(node.props["shortcut"])
                ))
            case "MenuBarExtra.Separator":
                items.append(.separator)
            case "MenuBarExtra.Section":
                if !items.isEmpty {
                    items.append(.separator)
                }
                items.append(MenuBarMenuItem(key: .header(node.id), role: .header, title: node.string("title") ?? ""))
                append(node.content, to: &items, icon: icon)
            case "MenuBarExtra.Submenu":
                var children: [MenuBarMenuItem] = []
                append(node.content, to: &children, icon: icon)
                items.append(MenuBarMenuItem(
                    key: .submenu(node.id),
                    role: .submenu(children),
                    title: node.string("title") ?? "",
                    icon: icon(node.props["icon"])
                ))
            default:
                break
            }
        }
    }
}

nonisolated extension Node {
    /// The first `MenuBarExtra` in the tree, found without collecting every descendant.
    var menuBarExtra: Node? {
        if type == "MenuBarExtra" {
            return self
        }
        for child in children {
            if let found = child.menuBarExtra {
                return found
            }
        }
        return nil
    }

    func descendant(id: Int) -> Node? {
        if self.id == id {
            return self
        }
        for child in children {
            if let found = child.descendant(id: id) {
                return found
            }
        }
        return nil
    }
}
