//
//  RenderReferenceTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// A render after the first names the subtrees the app already holds by id; these build trees from such renders.
struct RenderReferenceTests {
    private static func reference(_ id: Int) -> [String: Any] {
        ["ref": id]
    }

    /// An item with an action panel and a detail, the two slots a list repeats for every row.
    private static func item(_ title: String, id: Int) -> [String: Any] {
        Fixture.node("List.Item", id: id, props: ["title": title], children: [
            Fixture.node("_slot", id: id + 1, props: ["name": "actions"], children: [
                Fixture.node("ActionPanel", id: id + 2, children: [Fixture.action("Open \(title)", id: id + 3)]),
            ]),
            Fixture.node("_slot", id: id + 4, props: ["name": "detail"], children: [
                Fixture.node("List.Item.Detail", id: id + 5, props: ["markdown": "# \(title)"]),
            ]),
        ])
    }

    private static func root(screen: Int = 2, loading: Bool = false, _ items: [[String: Any]]) -> [String: Any] {
        Fixture.node("root", id: 0, children: [
            Fixture.node("_screen", id: screen, children: [
                Fixture.node("List", id: screen + 1, props: ["isLoading": loading], handlers: ["onSelectionChange"], children: items),
            ]),
        ])
    }

    private static func whole(_ sequence: Int, _ tree: [String: Any]) -> [String: Any] {
        ["type": "render", "sequence": sequence, "tree": tree]
    }

    private static func partial(_ sequence: Int, base: Int? = nil, version: Int = KeptRender.referenceVersion, _ tree: [String: Any]) -> [String: Any] {
        ["type": "render", "sequence": sequence, "base": base ?? sequence - 1, "references": version, "tree": tree]
    }

    private static func tree(_ message: DecodedHostMessage?) -> Node? {
        guard case let .render(tree) = message else { return nil }
        return tree
    }

    private static func isUnresolved(_ message: DecodedHostMessage?) -> Bool {
        guard case .unresolvedRender = message else { return false }
        return true
    }

    /// The tree as the host would write it, with keys sorted so two equal trees give equal bytes.
    private static func serialized(_ node: Node?) throws -> Data {
        func json(_ node: Node) -> [String: Any] {
            ["id": node.id, "type": node.type, "props": node.props, "handlers": node.handlers.sorted(), "children": node.children.map(json)]
        }
        return try JSONSerialization.data(withJSONObject: node.map(json) ?? [:], options: .sortedKeys)
    }

    private static let planets = [Self.item("Mercury", id: 10), Self.item("Venus", id: 20), Self.item("Earth", id: 30)]

    @Test func aReferenceIsReplacedByTheNodeKeptUnderItsId() throws {
        var kept = KeptRender()
        let first = try #require(Self.tree(kept.decode(Self.whole(1, Self.root(Self.planets)))))
        let second = try #require(Self.tree(kept.decode(Self.partial(2, Self.root(loading: true, [10, 20, 30].map(Self.reference))))))
        let list = try #require(ViewState.view(in: second))
        #expect(list.bool("isLoading"))
        #expect(list.children.map { $0.string("title") } == ["Mercury", "Venus", "Earth"])
        #expect(list.children[1].slot("actions")?.children.first?.string("title") == "Open Venus")
        #expect(try Self.serialized(list.children[2]) == Self.serialized(ViewState.view(in: first)?.children[2]))
    }

    @Test func aTreeBuiltFromReferencesEqualsTheSameTreeSentWhole() throws {
        let renamed = Fixture.node("List.Item", id: 20, props: ["title": "The morning star"], children: [Self.reference(21), Self.reference(24)])
        var kept = KeptRender()
        _ = kept.decode(Self.whole(1, Self.root(Self.planets)))
        let built = Self.tree(kept.decode(Self.partial(2, Self.root([Self.reference(30), renamed, Self.reference(10)]))))

        var changed = Self.item("Venus", id: 20)
        changed["props"] = ["title": "The morning star"]
        var fresh = KeptRender()
        let sent = Self.tree(fresh.decode(Self.whole(1, Self.root([Self.planets[2], changed, Self.planets[0]]))))
        #expect(built != nil)
        #expect(try Self.serialized(built) == Self.serialized(sent))

        let again = Self.tree(kept.decode(Self.partial(3, Self.root(loading: true, [30, 20, 10].map(Self.reference)))))
        let list = ViewState.view(in: again)
        #expect(list?.children.map { $0.string("title") } == ["Earth", "The morning star", "Mercury"], "what the second render built is what the third names")
        #expect(list?.children[1].slot("detail")?.string("markdown") == "# Venus")
    }

    @Test func aSubtreeNamedUnderAnotherParentIsFoundByItsId() throws {
        var kept = KeptRender()
        _ = kept.decode(Self.whole(1, Self.root(Self.planets)))
        let section = Fixture.node("List.Section", id: 40, props: ["title": "Inner"], children: [Self.reference(20), Self.reference(32)])
        let moved = try #require(Self.tree(kept.decode(Self.partial(2, Self.root([Self.reference(10), section])))))
        let found = try #require(moved.descendants(ofType: "List.Section").first)
        #expect(found.children.map(\.id) == [20, 32])
        #expect(found.children[1].type == "ActionPanel")
        #expect(found.children[1].children.first?.string("title") == "Open Earth")
    }

    @Test func aKeptNodeKeepsItsRevisionAndEveryNodeSentAnewGetsAnother() throws {
        var kept = KeptRender()
        let first = try #require(ViewState.view(in: Self.tree(kept.decode(Self.whole(1, Self.root(Self.planets))))))
        let renamed = Fixture.node("List.Item", id: 20, props: ["title": "The morning star"], children: [Self.reference(21), Self.reference(24)])
        let second = try #require(ViewState.view(in: Self.tree(kept.decode(Self.partial(2, Self.root([Self.reference(10), renamed, Self.reference(30)]))))))

        #expect(second.children[0].revision == first.children[0].revision)
        #expect(second.children[2].revision == first.children[2].revision)
        #expect(second.children[1].revision != first.children[1].revision, "the item was sent anew")
        #expect(second.children[1].children.map(\.revision) == first.children[1].children.map(\.revision), "its slots were only named")
        #expect(second.revision != first.revision, "a node above a change is itself sent anew")

        var again = KeptRender()
        let same = try #require(ViewState.view(in: Self.tree(again.decode(Self.whole(1, Self.root(Self.planets))))))
        let all = [first, second, same].flatMap { $0.descendants(ofType: "List.Item").map(\.revision) }
        #expect(Set(all).count == 7, "another host's nodes never share a revision, though their ids and contents do")
    }

    @MainActor
    @Test func aRowAndADetailCompareByRevisionAndWhatElseTheyDraw() throws {
        var kept = KeptRender()
        let first = try #require(ViewState.view(in: Self.tree(kept.decode(Self.whole(1, Self.root(Self.planets))))))
        let second = try #require(ViewState.view(in: Self.tree(kept.decode(Self.partial(2, Self.root(loading: true, [10, 20, 30].map(Self.reference)))))))
        var fresh = KeptRender()
        let resent = try #require(ViewState.view(in: Self.tree(fresh.decode(Self.whole(1, Self.root(Self.planets))))))

        func row(_ node: Node, selected: Bool = false, compact: Bool = false) -> ListRow {
            ListRow(node: node, assetsPath: "/assets", selected: selected, compact: compact)
        }
        let keptRowIsSame = row(first.children[0]) == row(second.children[0])
        #expect(keptRowIsSame)
        let resentRowIsSame = row(first.children[0]) == row(resent.children[0])
        #expect(!resentRowIsSame, "equal contents sent anew are not known to be equal")
        let selectionCounts = row(first.children[0]) == row(second.children[0], selected: true)
        #expect(!selectionCounts)
        let widthCounts = row(first.children[0]) == row(second.children[0], compact: true)
        #expect(!widthCounts)
        let anotherRow = row(first.children[0]) == row(first.children[1])
        #expect(!anotherRow)

        let detail = try #require(first.children[1].slot("detail"))
        let keptDetail = try #require(second.children[1].slot("detail"))
        let keptDetailIsSame = DetailBody(node: detail, assetsPath: "/assets") == DetailBody(node: keptDetail, assetsPath: "/assets")
        #expect(keptDetailIsSame)
        let resentDetail = try #require(resent.children[1].slot("detail"))
        let resentDetailIsSame = DetailBody(node: detail, assetsPath: "/assets") == DetailBody(node: resentDetail, assetsPath: "/assets")
        #expect(!resentDetailIsSame)
        #expect(Row(node: first.children[0], sectionTitle: nil) == Row(node: second.children[0], sectionTitle: nil))
        #expect(Row(node: first.children[0], sectionTitle: nil) != Row(node: second.children[0], sectionTitle: "Inner"))
    }

    @Test func aReferenceToNothingBuildsNoTreeAndIsReportedOnce() {
        var kept = KeptRender()
        _ = kept.decode(Self.whole(1, Self.root(Self.planets)))
        #expect(Self.isUnresolved(kept.decode(Self.partial(2, Self.root([Self.reference(10), Self.reference(99)])))))
        let whileWaiting = kept.decode(Self.partial(3, Self.root([Self.reference(10)])))
        #expect(whileWaiting == nil, "the whole render is already asked for")

        let recovered = Self.tree(kept.decode(Self.whole(4, Self.root(Self.planets))))
        #expect(recovered != nil)
        let after = Self.tree(kept.decode(Self.partial(5, Self.root([Self.reference(30)]))))
        #expect(ViewState.view(in: after)?.children.map(\.id) == [30])
        #expect(Self.isUnresolved(kept.decode(Self.partial(6, Self.root([Self.reference(99)])))), "a later miss is reported again")
    }

    @Test func aRenderWrittenAgainstOneTheAppMissedIsNotRead() {
        var kept = KeptRender()
        _ = kept.decode(Self.whole(1, Self.root(Self.planets)))
        #expect(Self.isUnresolved(kept.decode(Self.partial(3, base: 2, Self.root([Self.reference(10)])))), "every name resolves, but against the wrong render")

        var empty = KeptRender()
        #expect(Self.isUnresolved(empty.decode(Self.partial(1, base: 0, Self.root([])))), "a host that restarted is owed nothing by a new decoder")
    }

    @Test func referencesOfAnotherVersionAreNotRead() {
        var kept = KeptRender()
        _ = kept.decode(Self.whole(1, Self.root(Self.planets)))
        let newer = Self.partial(2, version: KeptRender.referenceVersion + 1, Self.root([Self.reference(10)]))
        #expect(Self.isUnresolved(kept.decode(newer)))
        var unversioned = Self.partial(2, Self.root([Self.reference(10)]))
        unversioned["references"] = nil
        var other = KeptRender()
        _ = other.decode(Self.whole(1, Self.root(Self.planets)))
        #expect(Self.isUnresolved(other.decode(unversioned)))
    }

    @Test func wholeRendersNeedNoSequenceAndMayNameNothing() {
        var kept = KeptRender()
        #expect(Self.tree(kept.decode(["type": "render", "tree": Self.root(Self.planets)])) != nil)
        let again = Self.tree(kept.decode(["type": "render", "tree": Self.root([Self.planets[0]])]))
        #expect(ViewState.view(in: again)?.children.map(\.id) == [10])
        #expect(Self.isUnresolved(kept.decode(["type": "render", "tree": Self.root([Self.reference(10)])])), "a whole render stands on its own")
    }

    @Test func aScreenThatWasReplacedIsNoLongerHeld() {
        var kept = KeptRender()
        _ = kept.decode(Self.whole(1, Self.root(Self.planets)))
        let pushed = Fixture.node("root", id: 0, children: [Fixture.node("_screen", id: 60, children: [Fixture.node("Detail", id: 61)])])
        #expect(Self.tree(kept.decode(Self.partial(2, pushed))) != nil)
        let popped = Fixture.node("root", id: 0, children: [Self.reference(2)])
        #expect(Self.isUnresolved(kept.decode(Self.partial(3, popped))), "only the last render is held, not every node ever seen")
    }

    @Test func theDecoderHoldsTheLastRenderBetweenChunksAndMissesWhatItCouldNotRead() async throws {
        func line(_ json: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: json) + Data("\n".utf8)
        }
        let decoder = HostMessageDecoder()
        _ = try await decoder.append(line(Self.whole(1, Self.root(Self.planets))))
        let second = try await decoder.append(line(Self.partial(2, Self.root(loading: true, [10, 20, 30].map(Self.reference)))))
        #expect(ViewState.view(in: Self.tree(second.first))?.children.map(\.id) == [10, 20, 30])

        let lost = await decoder.append(Data("{\"type\":\"render\",\"sequence\":3,\"tree\":\n".utf8))
        #expect(lost.isEmpty)
        let fourth = try await decoder.append(line(Self.partial(4, Self.root([Self.reference(10)]))))
        #expect(fourth.count == 1)
        #expect(Self.isUnresolved(fourth.first))
    }
}
