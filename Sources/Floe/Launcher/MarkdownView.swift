//
//  MarkdownView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

/// Draws Markdown that was parsed already. Nothing is parsed here: `content` is made when the text changes.
struct MarkdownView: View {
    let content: MarkdownContent
    /// Detail views keep the compact size; an answer that is read at length passes a larger one.
    var font = Font.system(size: 13)
    var lineSpacing: CGFloat = 0
    /// Selectable text does not draw off screen, so `--panel-snapshot` turns this off.
    static var isSelectable = true

    var body: some View {
        MarkdownBlocks(pieces: content.pieces, lineSpacing: lineSpacing)
            .font(font)
            .modifier(Selectable(isOn: Self.isSelectable))
    }
}

/// Markdown that arrives as text and seldom changes, parsed once per text and not once per evaluation.
struct MarkdownTextView: View {
    let text: String
    @State private var memo = MarkdownMemo()

    var body: some View {
        MarkdownView(content: memo.content(for: text))
    }
}

private struct Selectable: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

/// A run of blocks, drawn again inside a quote for the blocks it holds.
private struct MarkdownBlocks: View {
    let pieces: [MarkdownContent.Piece]
    let lineSpacing: CGFloat

    private func paragraph(_ string: AttributedString) -> some View {
        Text(string).lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true)
    }

    private func listRow(_ marker: String, _ string: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).foregroundStyle(.secondary).monospacedDigit()
            paragraph(string)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case let .heading(level, text):
                    Text(text).font(.system(size: [22, 18, 15][min(level, 3) - 1], weight: .semibold))
                case let .paragraph(text):
                    paragraph(text)
                case let .bullet(text):
                    listRow("•", text)
                case let .numbered(number, text):
                    listRow("\(number).", text)
                case let .quote(quoted):
                    // Type-erased: a view cannot hold itself in its own body's type.
                    AnyView(MarkdownBlocks(pieces: quoted, lineSpacing: lineSpacing))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                        }
                case let .code(text):
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 8))
                case let .image(url):
                    MarkdownImage(url: url)
                case .rule:
                    Divider()
                }
            }
        }
    }
}

/// A picture in the text, decoded no larger than it can be drawn: the panel's width, and 260 pt high.
private struct MarkdownImage: View {
    let url: URL
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    private static let maxHeight: CGFloat = 260
    /// Wider than the launcher's panel, so a wide picture is still sharp across it.
    private static let maxWidth: CGFloat = 900

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale).resizable().scaledToFit()
            } else {
                Color.primary.opacity(0.05)
            }
        }
        .frame(maxHeight: Self.maxHeight)
        .task(id: url) {
            image = nil
            image = await RemoteImage.picture(at: url, maxPixels: Int(Self.maxWidth * displayScale))
        }
    }
}
