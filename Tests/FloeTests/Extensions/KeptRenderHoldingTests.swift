//
//  KeptRenderHoldingTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// A render that refers to the last one changes the held nodes only where it sent nodes again. These check
/// that what is held after every render is what holding the whole new tree would give.
struct KeptRenderHoldingTests {
    private static func wholeRebuild(_ message: DecodedHostMessage?) -> [Int: Int] {
        guard case let .render(tree) = message else { return [:] }
        var held: [Int: Node] = [:]
        tree?.hold(in: &held)
        return held.mapValues(\.revision)
    }

    @Test func theRuntimesOwnRendersAreHeldAsAWholeRebuildWouldHoldThem() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("runtime/tests/fixtures/sent-lines.json")
        let lines = try JSONDecoder().decode([String].self, from: Data(contentsOf: fixture))
        #expect(lines.count > 10)
        var kept = KeptRender()
        for line in lines {
            let message = DecodedHostMessage.decode(Data(line.utf8), kept: &kept)
            if case .unresolvedRender = message {
                Issue.record("a recorded render could not be built")
            }
            #expect(kept.heldRevisions == Self.wholeRebuild(message))
        }
    }

    @Test func aNodeNamedUnderANewParentStaysHeldThoughItsOldParentLetItGo() {
        var kept = KeptRender()
        let item = Fixture.node("List.Item", id: 30, children: [Fixture.node("ActionPanel", id: 32)])
        _ = kept.decode(["type": "render", "sequence": 1, "tree": Fixture.node("root", id: 0, children: [
            Fixture.node("List", id: 1, children: [Fixture.node("List.Item", id: 20), item]),
        ])])
        // The new section comes first, so the panel is met by reference before its old parent drops it.
        let moved = Fixture.node("root", id: 0, children: [
            Fixture.node("List.Section", id: 40, children: [["ref": 32]]),
            Fixture.node("List", id: 1, children: [["ref": 20]]),
        ])
        let message = kept.decode(["type": "render", "sequence": 2, "base": 1, "references": 1, "tree": moved])
        #expect(kept.heldRevisions == Self.wholeRebuild(message))
        #expect(kept.heldRevisions[32] != nil)
        #expect(kept.heldRevisions[30] == nil)
        let again = Fixture.node("root", id: 0, children: [["ref": 40], ["ref": 1]])
        guard case .render = kept.decode(["type": "render", "sequence": 3, "base": 2, "references": 1, "tree": again]) else {
            Issue.record("the moved panel was not held")
            return
        }
    }

    @Test func aLongRunOfEditsIsHeldAsAWholeRebuildWouldHoldIt() {
        var host = SimulatedHost()
        var kept = KeptRender()
        var previous: [Int: Node] = [:]
        for round in 0 ..< 400 {
            host.edit()
            guard let rendered = host.render() else { continue }
            let message = kept.decode(rendered)
            if case .unresolvedRender = message {
                let old = try? Node(json: rendered["tree"], kept: previous)
                Issue.record("round \(round): a render could not be built; against the whole last tree it \(old == nil ? "fails too" : "builds")")
                return
            }
            if case let .render(tree) = message {
                previous = [:]
                tree?.hold(in: &previous)
            }
            #expect(kept.heldRevisions == Self.wholeRebuild(message))
        }
    }
}

/// A host in miniature: a tree edited at random and written the way the runtime writes it, an unchanged
/// subtree the app holds named by reference. Seeded, so a failure repeats.
private struct SimulatedHost {
    private final class Element {
        let id: Int
        var title: String
        var children: [Element] = []
        var changed = true

        init(id: Int, title: String) {
            self.id = id
            self.title = title
        }
    }

    private var random = SplitMix(seed: 7)
    private var nextID = 1
    private let root = Element(id: 0, title: "root")
    private var held: Set<Int> = []
    private var sequence = 0

    init() {
        for _ in 0 ..< 6 {
            root.children.append(make(depth: 2))
        }
    }

    private mutating func make(depth: Int) -> Element {
        let element = Element(id: nextID, title: "node \(nextID)")
        nextID += 1
        if depth > 0 {
            for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
                element.children.append(make(depth: depth - 1))
            }
        }
        return element
    }

    private func all(_ element: Element) -> [Element] {
        [element] + element.children.flatMap(all)
    }

    private func path(to target: Element, from element: Element) -> [Element]? {
        if element === target {
            return [element]
        }
        for child in element.children {
            if let below = path(to: target, from: child) {
                return [element] + below
            }
        }
        return nil
    }

    private func touch(_ element: Element) {
        path(to: element, from: root)?.forEach { $0.changed = true }
    }

    mutating func edit() {
        let elements = all(root)
        let target = elements.randomElement(using: &random)!
        switch Int.random(in: 0 ..< 5, using: &random) {
        case 0:
            target.title += "'"
            touch(target)
        case 1 where !target.children.isEmpty:
            target.children.remove(at: Int.random(in: 0 ..< target.children.count, using: &random))
            touch(target)
        case 2:
            target.children.insert(make(depth: 1), at: Int.random(in: 0 ... target.children.count, using: &random))
            touch(target)
        case 3 where target.children.count > 1:
            target.children.shuffle(using: &random)
            touch(target)
        default:
            // A subtree moved under another parent, which the host may name there by reference.
            let candidates = elements.filter { $0 !== root && path(to: target, from: $0) == nil }
            guard let moving = candidates.randomElement(using: &random), let parent = elements.first(where: { $0.children.contains { $0 === moving } }) else { return }
            parent.children.removeAll { $0 === moving }
            touch(parent)
            target.children.append(moving)
            touch(target)
        }
    }

    /// Nil when nothing changed, which the runtime does not send either.
    mutating func render() -> [String: Any]? {
        guard root.changed || sequence == 0 else { return nil }
        sequence += 1
        func write(_ element: Element) -> [String: Any] {
            if !element.changed, held.contains(element.id) {
                return ["ref": element.id]
            }
            return Fixture.node("Item", id: element.id, props: ["title": element.title], children: element.children.map(write))
        }
        let tree = write(root)
        let first = sequence == 1
        all(root).forEach { $0.changed = false }
        held = Set(all(root).map(\.id))
        return first ? ["type": "render", "sequence": sequence, "tree": tree] : ["type": "render", "sequence": sequence, "base": sequence - 1, "references": 1, "tree": tree]
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
