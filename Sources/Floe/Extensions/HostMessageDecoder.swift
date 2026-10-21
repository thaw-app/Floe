//
//  HostMessageDecoder.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One host message with its decoding work already done: a render whose tree is built, or any other
/// message with its fields as the host sent them.
///
/// The unchecked Sendable is sound because `decode` is the only way to make one: it derives every
/// stored value from bytes run through `JSONSerialization` with the default options, so they are
/// fresh, immutable, JSON-only objects owned solely by this value and never mutated afterwards.
/// It must never be extended to carry caller-supplied objects.
nonisolated enum DecodedHostMessage: @unchecked Sendable {
    case render(tree: Node?)
    /// A render that names nodes the app does not hold: nothing to show, the host is asked for a whole one.
    case unresolvedRender
    case fields([String: Any])
    /// A line still unfinished past the decoder's limit: what came of it is dropped, and the host is stopped.
    case oversized(bytes: Int)

    /// Decodes one complete NDJSON line. Nil for anything JSON cannot read into an object, which the
    /// host's output has always skipped.
    static func decode(_ line: Data, kept: inout KeptRender) -> DecodedHostMessage? {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        if message["type"] as? String == "render" {
            return kept.decode(message)
        }
        return .fields(message)
    }
}

/// The nodes of the last render the decoder built, by id: what a reference in the next render stands for.
/// Its nodes are shared with the trees handed on, which is sound for the reason above: nothing mutates them.
nonisolated struct KeptRender {
    /// The references this app reads. The host is told, and sends whole renders to an app that reads another kind.
    static let referenceVersion = 1

    private var nodes: [Int: Node] = [:]
    private var root: Node?
    private var sequence: Int?
    private var hasAsked = false

    /// Nil for a render that cannot be built while a whole one is already on its way.
    mutating func decode(_ message: [String: Any]) -> DecodedHostMessage? {
        let tree: Node?
        do {
            tree = try Node(json: message["tree"], kept: keptNodes(for: message))
        } catch {
            defer { hasAsked = true }
            return hasAsked ? nil : .unresolvedRender
        }
        // Only this render is held, as the host assumes: a screen it left out is sent whole when it comes back.
        // A render that refers to the last one changes the held nodes where it sent nodes again.
        if message["base"] != nil, let tree, root?.id == tree.id {
            Self.refresh(tree, in: &nodes)
        } else {
            var held: [Int: Node] = [:]
            held.reserveCapacity(nodes.count)
            tree?.hold(in: &held)
            nodes = held
        }
        root = tree
        sequence = message["sequence"] as? Int
        hasAsked = false
        return .render(tree: tree)
    }

    /// The ids held and the revision of each, for a test that compares them with a whole rebuild.
    var heldRevisions: [Int: Int] {
        nodes.mapValues(\.revision)
    }

    /// Changes the held nodes where this render sent nodes again; a referenced subtree is held already.
    /// Drops come before filing, since a subtree may move under another parent.
    private static func refresh(_ tree: Node, in held: inout [Int: Node]) {
        dropRemoved(under: tree, from: &held)
        file(tree, in: &held)
    }

    private static func dropRemoved(under node: Node, from held: inout [Int: Node]) {
        let old = held[node.id]
        guard old?.revision != node.revision else { return }
        // Mostly the same children in the same order, which needs no set to tell.
        if let old, !old.children.elementsEqual(node.children, by: { $0.id == $1.id }) {
            let kept = Set(node.children.map(\.id))
            for child in old.children where !kept.contains(child.id) {
                drop(child, from: &held)
            }
        }
        for child in node.children {
            dropRemoved(under: child, from: &held)
        }
    }

    private static func file(_ node: Node, in held: inout [Int: Node]) {
        guard held[node.id]?.revision != node.revision else { return }
        held[node.id] = node
        for child in node.children {
            file(child, in: &held)
        }
    }

    private static func drop(_ node: Node, from held: inout [Int: Node]) {
        held[node.id] = nil
        for child in node.children {
            drop(child, from: &held)
        }
    }

    /// A whole render names nothing. One with references is only good against the render it was written
    /// for, and only in the form this app reads.
    private func keptNodes(for message: [String: Any]) throws(Node.UnresolvedReference) -> [Int: Node] {
        guard let base = message["base"] else { return [:] }
        guard let sequence, base as? Int == sequence, message["references"] as? Int == Self.referenceVersion else {
            throw Node.UnresolvedReference()
        }
        return nodes
    }
}

/// Frames the host's NDJSON stdout and decodes each complete line, away from the main actor.
/// One decoder per running host: it owns the partial bytes between chunks.
actor HostMessageDecoder {
    /// The longest line kept while it waits for its newline. The memory watchdog watches only the host,
    /// so a host writing one line without end would otherwise grow Floe instead.
    static let lineLimit = 256 << 20

    private let lineLimit: Int
    private var kept = KeptRender()
    private var buffer = Data()
    /// Set once a line ran past the limit: the rest of the output is not read.
    private var isRefusing = false
    /// Bytes already searched for a newline, counted from buffer.startIndex, so an incomplete long
    /// line is not rescanned on every chunk.
    private var scanned = 0

    init(lineLimit: Int = HostMessageDecoder.lineLimit) {
        self.lineLimit = lineLimit
    }

    /// Hands back the messages this chunk completed, in arrival order.
    func append(_ data: Data) -> [DecodedHostMessage] {
        guard !isRefusing else { return [] }
        buffer.append(data)
        var messages: [DecodedHostMessage] = []
        var search = buffer.index(buffer.startIndex, offsetBy: scanned)
        // range(of:in:) reports positions in the buffer's own index space, which a sliced subscript
        // would not: Data slices restart their indices at zero.
        var lineStart = buffer.startIndex
        while let newline = buffer.range(of: Data([0x0A]), in: search ..< buffer.endIndex)?.lowerBound {
            if let message = DecodedHostMessage.decode(buffer.subdata(in: lineStart ..< newline), kept: &kept) {
                messages.append(message)
            }
            search = buffer.index(after: newline)
            lineStart = search
        }
        // [start, lineStart) holds finished lines, [lineStart, end) a partial line that has been
        // searched already. Compaction may only drop the finished part — dropping searched bytes of
        // the partial line would lose them — and scanned is counted from lineStart after that.
        scanned = buffer.distance(from: lineStart, to: buffer.endIndex)
        if lineStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex ..< lineStart)
        }
        if buffer.count > lineLimit {
            messages.append(.oversized(bytes: buffer.count))
            isRefusing = true
            buffer = Data()
            scanned = 0
        }
        return messages
    }
}

extension HostMessageDecoder {
    /// Feeds one stdout chunk and applies whatever it completes, in order, before returning. Awaiting
    /// each application keeps the next chunk from overtaking the one being applied.
    func deliver(_ data: Data, applying: @Sendable (DecodedHostMessage) async -> Void) async {
        for message in append(data) {
            await applying(message)
        }
    }
}
