//
//  SessionGridTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The arrow keys in a Grid move through its lines and columns; in a List they only go up and down.
@MainActor
struct SessionGridTests {
    private let session = ExtensionSession(command: Fixture.command("icons"))

    private func render(_ type: String, count: Int) {
        var kept = KeptRender()
        let items = (1 ... count).map { Fixture.node("\(type).Item", props: ["title": "Item \($0)"]) }
        let view = Fixture.node(type, id: 1, props: ["columns": 3], children: items)
        let json: [String: Any] = ["type": "render", "tree": Fixture.node("root", id: 0, children: [Fixture.node("_screen", id: 50, children: [view])])]
        guard let encoded = try? JSONSerialization.data(withJSONObject: json), let message = DecodedHostMessage.decode(encoded, kept: &kept) else {
            Issue.record("the render is not representable")
            return
        }
        session.apply(message)
    }

    @Test func downGoesALineAndRightTheNextItem() {
        render("Grid", count: 7)
        session.moveSelection(by: 1)
        #expect(session.selection == 3)
        #expect(session.stepInGrid(by: 1))
        #expect(session.selection == 4)
        session.moveSelection(by: 1)
        #expect(session.selection == 6, "the last line has one item")
    }

    @Test func aListLeavesLeftAndRightToTheSearchField() {
        render("List", count: 7)
        #expect(session.gridLayout == nil)
        #expect(session.stepInGrid(by: 1) == false)
        session.moveSelection(by: 1)
        #expect(session.selection == 1)
    }
}
