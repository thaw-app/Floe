//
//  MenuBarPresenter.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The part of a status bar button a menu-bar command draws in; tests stand in for it.
@MainActor protocol MenuBarStatusButton: AnyObject {
    var title: String { get set }
    var image: NSImage? { get set }
    var toolTip: String? { get set }
}

extension NSStatusBarButton: MenuBarStatusButton {}

/// A menu that is filled when it opens. `pending` is what a submenu shows the next time it does.
final class MenuBarMenu: NSMenu {
    var pending: [MenuBarMenuItem]?
    var isOpen = false

    /// AppKit's initializers are nonisolated, and so must be the ones that override them.
    override nonisolated init(title: String) {
        super.init(title: title)
    }

    required nonisolated init(coder: NSCoder) {
        super.init(coder: coder)
    }
}

/// Draws one menu-bar command: the status button on every render, the menu only when someone looks at it.
@MainActor final class MenuBarPresenter: NSObject, NSMenuDelegate {
    let menu = MenuBarMenu()
    var onAction: (Int) -> Void = { _ in
        // Set by MenuBarCommands.
    }

    /// Called once each time the command's own menu opens, not for its submenus.
    var onOpen: () -> Void = {
        // Set by MenuBarCommands.
    }

    var onRetry: () -> Void = {
        // Set by MenuBarCommands.
    }

    var onRemove: () -> Void = {
        // Set by MenuBarCommands.
    }

    var commandTitle: String {
        didSet {
            guard commandTitle != oldValue else { return }
            updateButton()
            menuChanged()
        }
    }

    /// How many times the menu's rows were worked out and applied.
    private(set) var menuBuilds = 0

    private weak var button: (any MenuBarStatusButton)?
    private let images: MenuBarIconImages
    private let resolver: () -> MenuBarIconResolver
    private var root: Node?
    private var failure: SessionFailure?
    private var shown: MenuBarStatusContent?
    private var shownTitle: String
    private var hasImage = false
    private var isStale = true
    private var loading: Set<MenuBarIcon> = []

    init(button: (any MenuBarStatusButton)?, commandTitle: String, images: MenuBarIconImages, resolver: @escaping () -> MenuBarIconResolver) {
        self.button = button
        self.commandTitle = commandTitle
        self.images = images
        self.resolver = resolver
        self.shownTitle = commandTitle
        super.init()
        menu.delegate = self
        button?.title = commandTitle
        updateButton()
    }

    func show(root: Node?) {
        self.root = root
        updateButton()
        menuChanged()
    }

    func show(failure: SessionFailure?) {
        guard failure != self.failure else { return }
        self.failure = failure
        menuChanged()
    }

    // MARK: Status button

    private func updateButton() {
        let resolver = resolver()
        let content = MenuBarStatusContent(root: root, previous: shown, icon: resolver.icon(for:))
        let changes = content.changes(from: shown)
        shown = content
        if changes.contains(.image) {
            let image = content.icon.flatMap { images.now($0, for: .statusButton) }
            // An icon that cannot be drawn after one that could not either changes nothing on the button.
            if image != nil || hasImage {
                button?.image = image
            }
            hasImage = image != nil
        }
        let title = content.shownTitle(hasImage: hasImage, commandTitle: commandTitle)
        if title != shownTitle {
            shownTitle = title
            button?.title = title
        }
        if changes.contains(.toolTip), let toolTip = content.toolTip {
            button?.toolTip = toolTip
        }
    }

    // MARK: Menu

    /// A closed menu only notes that it is out of date; an open one is brought up to date in place.
    private func menuChanged() {
        isStale = true
        if menu.isOpen {
            rebuildIfStale()
        }
    }

    private func rebuildIfStale() {
        guard isStale else { return }
        isStale = false
        menuBuilds += 1
        let resolver = resolver()
        apply(MenuBarMenuItem.items(root: root, failure: failure, commandTitle: commandTitle, icon: resolver.icon(for:)), to: menu)
    }

    /// Rows that are still there keep their `NSMenuItem`, so the highlight and an open submenu stay put.
    private func apply(_ items: [MenuBarMenuItem], to menu: MenuBarMenu) {
        menu.pending = nil
        let current = menu.items.map { ($0.representedObject as? MenuBarMenuItem)?.key ?? .separator }
        for change in items.map(\.key).difference(from: current) {
            switch change {
            case let .remove(offset, _, _):
                menu.removeItem(at: offset)
            case let .insert(offset, _, _):
                menu.insertItem(makeItem(for: items[offset].role), at: offset)
            }
        }
        for (item, wanted) in zip(menu.items, items) {
            update(item, to: wanted)
        }
    }

    private func makeItem(for role: MenuBarMenuItem.Role) -> NSMenuItem {
        switch role {
        case .separator: .separator()
        case .header: .sectionHeader(title: "")
        default: NSMenuItem()
        }
    }

    private func update(_ item: NSMenuItem, to wanted: MenuBarMenuItem) {
        let old = item.representedObject as? MenuBarMenuItem
        guard old != wanted else { return }
        item.representedObject = wanted
        if old?.title != wanted.title {
            item.title = wanted.title
        }
        if old?.subtitle != wanted.subtitle {
            item.subtitle = wanted.subtitle
        }
        if old?.toolTip != wanted.toolTip {
            item.toolTip = wanted.toolTip
        }
        if old?.icon != wanted.icon {
            setImage(of: item, to: wanted.icon)
        }
        if old?.shortcut != wanted.shortcut {
            item.keyEquivalent = wanted.shortcut?.key ?? ""
            item.keyEquivalentModifierMask = wanted.shortcut?.flags ?? []
        }
        if old?.role != wanted.role {
            setRole(of: item, to: wanted.role)
        }
    }

    private func setRole(of item: NSMenuItem, to role: MenuBarMenuItem.Role) {
        switch role {
        case let .action(node):
            item.target = self
            item.action = #selector(fire(_:))
            item.tag = node
            item.isEnabled = true
        case .disabled:
            item.target = nil
            item.action = nil
            item.isEnabled = false
        case .retry:
            item.target = self
            item.action = #selector(retry(_:))
        case .remove:
            item.target = self
            item.action = #selector(remove(_:))
        case let .submenu(children):
            let submenu = item.submenu as? MenuBarMenu ?? makeSubmenu(of: item)
            if submenu.isOpen {
                apply(children, to: submenu)
            } else {
                submenu.pending = children
            }
        case .separator, .header:
            break
        }
    }

    private func makeSubmenu(of item: NSMenuItem) -> MenuBarMenu {
        let submenu = MenuBarMenu()
        submenu.delegate = self
        item.submenu = submenu
        return submenu
    }

    // MARK: Icons

    /// A cached icon is set in this pass. Any other is made in the background and filled in, so a
    /// large menu opening for the first time does not wait on its images.
    private func setImage(of item: NSMenuItem, to icon: MenuBarIcon?) {
        guard let icon else {
            item.image = nil
            return
        }
        if let image = images.cached(icon, for: .menuItem) {
            item.image = image
            return
        }
        if item.image == nil {
            item.image = MenuBarIconImages.placeholder
        }
        guard loading.insert(icon).inserted else { return }
        Task { [weak self, images] in
            let image = await images.load(icon, for: .menuItem)
            guard let self else { return }
            loading.remove(icon)
            fill(icon, with: image, in: menu)
        }
    }

    private func fill(_ icon: MenuBarIcon, with image: NSImage?, in menu: NSMenu) {
        for item in menu.items {
            if (item.representedObject as? MenuBarMenuItem)?.icon == icon {
                item.image = image
            }
            if let submenu = item.submenu {
                fill(icon, with: image, in: submenu)
            }
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menu = menu as? MenuBarMenu else { return }
        if menu === self.menu {
            rebuildIfStale()
        } else if let pending = menu.pending {
            apply(pending, to: menu)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuNeedsUpdate(menu)
        guard let menu = menu as? MenuBarMenu, !menu.isOpen else { return }
        menu.isOpen = true
        if menu === self.menu {
            onOpen()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        (menu as? MenuBarMenu)?.isOpen = false
    }

    /// No row has a key equivalent, and saying so keeps AppKit from filling the menu to look for one.
    func menuHasKeyEquivalent(_: NSMenu, for _: NSEvent, target _: AutoreleasingUnsafeMutablePointer<AnyObject?>, action _: UnsafeMutablePointer<Selector?>) -> Bool {
        false
    }

    @objc private func fire(_ sender: NSMenuItem) {
        onAction(sender.tag)
    }

    @objc private func retry(_: NSMenuItem) {
        onRetry()
    }

    @objc private func remove(_: NSMenuItem) {
        onRemove()
    }
}
