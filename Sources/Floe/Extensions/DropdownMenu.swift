//
//  DropdownMenu.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// A list's dropdown as a menu that is only built when it is opened. An extension sends the whole dropdown with
/// every render, and one with hundreds of items made SwiftUI's own menu rebuild them each time.
enum DropdownMenu {
    enum Entry: Equatable {
        case heading(String)
        case item(title: String, value: String)
    }

    /// The dropdown's items in order, each section under its title.
    static nonisolated func entries(for node: Node) -> [Entry] {
        node.children.flatMap { child -> [Entry] in
            if child.type.hasSuffix("Dropdown.Section") {
                let heading = child.string("title").map { [Entry.heading($0)] } ?? []
                return heading + entries(for: child)
            }
            guard child.type.hasSuffix("Dropdown.Item") else { return [] }
            return [.item(title: child.string("title") ?? "", value: child.props["value"] as? String ?? "")]
        }
    }

    /// The title of the chosen item, for the button that opens the menu.
    static nonisolated func title(of value: String?, in entries: [Entry]) -> String? {
        for case let .item(title, itemValue) in entries where itemValue == value {
            return title
        }
        return nil
    }

    /// The menu, with a check beside the chosen item. `choose` is called with the value of the item picked.
    static func menu(_ entries: [Entry], current: String?, choose: @escaping (String) -> Void) -> (menu: NSMenu, chosen: NSMenuItem?) {
        let menu = NSMenu()
        let target = Target(choose: choose)
        var chosen: NSMenuItem?
        for entry in entries {
            switch entry {
            case let .heading(title):
                if !menu.items.isEmpty {
                    menu.addItem(.separator())
                }
                menu.addItem(.sectionHeader(title: title))
            case let .item(title, value):
                let item = NSMenuItem(title: title, action: #selector(Target.picked(_:)), keyEquivalent: "")
                item.target = target
                item.representedObject = value
                if value == current, chosen == nil {
                    item.state = .on
                    chosen = item
                }
                menu.addItem(item)
            }
        }
        // The menu keeps what its items call alive for as long as it is open.
        objc_setAssociatedObject(menu, &targetKey, target, .OBJC_ASSOCIATION_RETAIN)
        return (menu, chosen)
    }

    /// Opens the menu under the pointer, on the chosen item when there is one.
    static func open(_ entries: [Entry], current: String?, choose: @escaping (String) -> Void) {
        let built = menu(entries, current: current, choose: choose)
        built.menu.popUp(positioning: built.chosen, at: NSEvent.mouseLocation, in: nil)
    }

    private static nonisolated(unsafe) var targetKey: UInt8 = 0

    private final class Target: NSObject {
        let choose: (String) -> Void

        init(choose: @escaping (String) -> Void) {
            self.choose = choose
        }

        @objc func picked(_ item: NSMenuItem) {
            if let value = item.representedObject as? String {
                choose(value)
            }
        }
    }
}
