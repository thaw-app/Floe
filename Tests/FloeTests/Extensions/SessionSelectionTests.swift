//
//  SessionSelectionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// onSelectionChange, selectedItemId and pagination, with the messages a host would send.
@MainActor
struct SessionSelectionTests {
    private final class Recorder {
        var sent: [[String: Any]] = []
        var kept = KeptRender()

        func events(_ prop: String) -> [[String: Any]] {
            sent.filter { $0["type"] as? String == "event" && $0["prop"] as? String == prop }
        }
    }

    private let session = ExtensionSession(command: Fixture.command("planets"))
    private let recorder = Recorder()

    init() {
        session.transport = { [recorder] in recorder.sent.append($0) }
    }

    private func render(_ props: [String: Any], handlers: [String], ids: [String]) {
        let items = ids.map { Fixture.node("List.Item", props: ["title": $0.capitalized, "id": $0]) }
        let list = Fixture.node("List", id: 1, props: props, handlers: handlers, children: items)
        let json: [String: Any] = ["type": "render", "tree": Fixture.node("root", id: 0, children: [Fixture.node("_screen", id: 50, children: [list])])]
        guard let encoded = try? JSONSerialization.data(withJSONObject: json), let message = DecodedHostMessage.decode(encoded, kept: &recorder.kept) else {
            Issue.record("the render is not representable")
            return
        }
        session.apply(message)
    }

    @Test func theSelectedItemsIDIsToldOnceEachTimeItChanges() {
        render([:], handlers: ["onSelectionChange"], ids: ["mars", "venus"])
        #expect(recorder.events("onSelectionChange").map { $0["args"] as? [String] } == [["mars"]])

        session.selection = 1
        session.selection = 1
        render([:], handlers: ["onSelectionChange"], ids: ["mars", "venus"])
        #expect(recorder.events("onSelectionChange").map { $0["args"] as? [String] } == [["mars"], ["venus"]], "the same item is not told twice")
    }

    @Test func noSelectionIsToldAsNull() {
        render([:], handlers: ["onSelectionChange"], ids: ["mars"])
        render([:], handlers: ["onSelectionChange"], ids: [])
        #expect(recorder.events("onSelectionChange").last?["args"] as? [NSNull] == [NSNull()])
    }

    @Test func selectedItemIdMovesTheSelectionOnceTheItemIsThere() {
        render(["selectedItemId": "venus"], handlers: [], ids: ["mars"])
        #expect(session.selection == 0)
        render(["selectedItemId": "venus"], handlers: [], ids: ["mars", "venus"])
        #expect(session.selection == 1)

        session.selection = 0
        render(["selectedItemId": "venus"], handlers: [], ids: ["mars", "venus"])
        #expect(session.selection == 0, "the user may move away from it until it names another")
    }

    @Test func theNextPageIsAskedForOncePerPageWhileThereIsOneAndNoneIsLoading() {
        render(["hasMore": true], handlers: ["onLoadMore"], ids: ["a", "b"])
        session.loadMore()
        session.loadMore()
        #expect(recorder.events("onLoadMore").count == 1)

        render(["hasMore": true, "isLoading": true], handlers: ["onLoadMore"], ids: ["a", "b", "c"])
        session.loadMore()
        #expect(recorder.events("onLoadMore").count == 1, "not while the page is loading")

        render(["hasMore": true], handlers: ["onLoadMore"], ids: ["a", "b", "c"])
        session.loadMore()
        render(["hasMore": false], handlers: ["onLoadMore"], ids: ["a", "b", "c", "d"])
        session.loadMore()
        #expect(recorder.events("onLoadMore").count == 2, "and not past the last page")
    }
}
