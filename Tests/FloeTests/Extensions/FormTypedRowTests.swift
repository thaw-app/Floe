//
//  FormTypedRowTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import SwiftUI
import Testing

/// Lays a grouped form out in a view that is in no window, and reads where AppKit put its fields.
@MainActor
struct FormTypedRowTests {
    private static let width: CGFloat = 700

    private func laidOut(_ form: some View) -> NSView {
        let host = NSHostingView(rootView: Form { form }.formStyle(.grouped).frame(width: Self.width, height: 400))
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    @Test func aTextAreaTakesTheRowAndNotItsTrailingHalf() throws {
        let root = laidOut(FormTextArea(title: "Input", text: .constant("x^2 ")))
        let box = try #require(views(NSTextView.self, in: root).first?.enclosingScrollView)
        let frame = box.convert(box.bounds, to: root)
        #expect(frame.width > Self.width * 0.8, "the box is \(frame.width) wide")
        #expect(frame.minX < Self.width * 0.2, "it starts after the title, at \(frame.minX)")
    }

    @Test func textInATypedRowStartsAtTheLeadingEdge() {
        let root = laidOut(Group {
            FormTypedRow(title: "Name") { TextField("Name", text: .constant("abc")) }
            FormTypedRow(title: "Secret") { SecureField("Secret", text: .constant("abc")) }
        })
        let alignments = views(NSTextField.self, in: root).filter(\.isEditable).map(\.alignment)
        #expect(alignments == [.natural, .natural])
    }
}
