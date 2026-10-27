//
//  MarkdownContent.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Markdown ready to draw: its blocks, each with the inline styling already worked out.
/// Made when the text changes, so a view that is evaluated again has nothing to parse.
nonisolated struct MarkdownContent: Equatable, Sendable {
    /// A block as it is drawn. The same cases as `MarkdownBlock`, with styled text in place of source.
    enum Piece: Equatable, Sendable {
        case heading(Int, AttributedString)
        case paragraph(AttributedString)
        case bullet(AttributedString)
        case numbered(Int, AttributedString)
        case quote([Piece])
        case code(String)
        case image(URL)
        case rule
    }

    static let empty = MarkdownContent(text: "", blocks: [], pieces: [])

    /// The source this was parsed from.
    let text: String
    let blocks: [MarkdownBlock]
    /// One piece per block, in the same order.
    let pieces: [Piece]

    private init(text: String, blocks: [MarkdownBlock], pieces: [Piece]) {
        self.text = text
        self.blocks = blocks
        self.pieces = pieces
    }

    /// A streaming answer grows at its end, so a block equal to the one `previous` has in its place keeps that piece.
    init(_ text: String, reusing previous: MarkdownContent = .empty) {
        let blocks = MarkdownParser.blocks(text)
        let pieces = blocks.enumerated().map { index, block in
            index < previous.blocks.count && previous.blocks[index] == block ? previous.pieces[index] : Piece(block)
        }
        self.init(text: text, blocks: blocks, pieces: pieces)
    }

    /// A picture's address as a link, for text whose pictures are not fetched: it opens only when clicked.
    static func link(to url: URL) -> AttributedString {
        var text = AttributedString(url.absoluteString)
        text.link = url
        return text
    }

    /// The same as `init(_:reusing:)`, run away from the caller's actor.
    @concurrent
    static func parsed(_ text: String, reusing previous: MarkdownContent) async -> MarkdownContent {
        MarkdownContent(text, reusing: previous)
    }
}

nonisolated extension MarkdownContent.Piece {
    init(_ block: MarkdownBlock) {
        switch block {
        case let .heading(level, text): self = .heading(level, Self.inline(text))
        case let .paragraph(text): self = .paragraph(Self.inline(text))
        case let .bullet(text): self = .bullet(Self.inline(text))
        case let .numbered(number, text): self = .numbered(number, Self.inline(text))
        case let .quote(quoted): self = .quote(quoted.map(Self.init))
        case let .code(text): self = .code(text)
        case let .image(url): self = .image(url)
        case .rule: self = .rule
        }
    }

    private static func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(string)
    }
}

/// Keeps the content of the last text it was asked for, for a view whose Markdown seldom changes.
final class MarkdownMemo {
    private var last = MarkdownContent.empty
    private let parse: (String) -> MarkdownContent

    init(parse: @escaping (String) -> MarkdownContent = { MarkdownContent($0) }) {
        self.parse = parse
    }

    func content(for text: String) -> MarkdownContent {
        if text != last.text {
            last = parse(text)
        }
        return last
    }
}
