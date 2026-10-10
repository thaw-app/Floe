//
//  Node.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Synchronization

/// One for every node built, across hosts: a restarted host counts its ids from one again.
private nonisolated let revisions = Atomic<Int>(0)

/// One element of the tree the Bun host serializes after each React commit.
nonisolated struct Node: Identifiable {
    let id: Int
    let type: String
    let props: [String: Any]
    let handlers: Set<String>
    let children: [Node]
    /// Stamped when the node is built from what the host sent, and kept while later renders only name it:
    /// two nodes with the same revision are the same subtree, which props of `Any` cannot say.
    let revision: Int

    init?(json: Any?) {
        guard let node = try? Node(json: json, kept: [:]) else { return nil }
        self = node
    }

    /// A child the host named by id because the app already holds it, and nothing is held under that id.
    struct UnresolvedReference: Error {}

    /// Builds what the host sent, putting a node of `kept` wherever a child is `{ "ref": id }`.
    init?(json: Any?, kept: [Int: Node]) throws(UnresolvedReference) {
        guard let fields = json as? [String: Any] else { return nil }
        try self.init(fields: fields, kept: kept)
    }

    /// Takes the fields already cast: bridging a JSON object costs as much as building the node from it.
    private init?(fields: [String: Any], kept: [Int: Node]) throws(UnresolvedReference) {
        guard let type = fields["type"] as? String else { return nil }
        self.id = fields["id"] as? Int ?? -1
        self.type = type
        self.props = fields["props"] as? [String: Any] ?? [:]
        self.handlers = Set(fields["handlers"] as? [String] ?? [])
        var children: [Node] = []
        for case let child as [String: Any] in fields["children"] as? [Any] ?? [] {
            if let id = child["ref"] as? Int {
                guard let node = kept[id] else { throw UnresolvedReference() }
                children.append(node)
            } else if let node = try Node(fields: child, kept: kept) {
                children.append(node)
            }
        }
        self.children = children
        self.revision = revisions.add(1, ordering: .relaxed).newValue
    }

    /// Files the node and everything under it by id, for the next render to name.
    func hold(in held: inout [Int: Node]) {
        held[id] = self
        for child in children {
            child.hold(in: &held)
        }
    }

    /// Element-valued props such as `actions` or `detail` arrive as named `_slot` children.
    func slot(_ name: String) -> Node? {
        children.first { $0.type == "_slot" && $0.props["name"] as? String == name }?.children.first
    }

    var content: [Node] {
        children.filter { $0.type != "_slot" }
    }

    /// Raycast accepts either a plain string or `{ value, tooltip }` for most text props.
    func string(_ key: String) -> String? {
        if let string = props[key] as? String {
            return string
        }
        return (props[key] as? [String: Any])?["value"] as? String
    }

    func bool(_ key: String) -> Bool {
        props[key] as? Bool ?? false
    }

    func descendants(ofType type: String) -> [Node] {
        (self.type == type ? [self] : []) + children.flatMap { $0.descendants(ofType: type) }
    }
}

nonisolated struct Row: Identifiable, Equatable {
    let node: Node
    let sectionTitle: String?
    var id: Int {
        node.id
    }

    /// The same item as the host last sent it, under the same section.
    static func == (lhs: Row, rhs: Row) -> Bool {
        lhs.node.revision == rhs.node.revision && lhs.sectionTitle == rhs.sectionTitle
    }
}
