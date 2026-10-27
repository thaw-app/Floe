//
//  MarkdownContentTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct MarkdownContentTests {
    /// One of everything the view draws, as an answer would use them.
    static nonisolated let document = """
    # Tides

    The sea rises and falls **twice a day**, as `high` and *low* water. See [the table](https://example.com/t).

    4. The Moon pulls the water nearest to it.
    5. A second bulge forms on the far side.
       - with a point **inside**

    > The Sun does the same.
    >
    > - at half the strength

    - Spring tides
    - Neap tides

    ```swift
    let period = 12.42
    ```

    ![A chart](https://example.com/chart.png)

    | a | b |
    |---|---|
    | 1 | 2 |

    ---
    The end.
    """

    private func styled(_ markdown: String) throws -> AttributedString {
        try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }

    @Test(arguments: [document, AskAI.sampleAnswer, "", "plain", "```\nunfinished", "> a\n> > b"])
    func theContentHoldsTheBlocksTheParserFindsAndOnePieceForEach(text: String) {
        let content = MarkdownContent(text)
        #expect(content.text == text)
        #expect(content.blocks == MarkdownParser.blocks(text))
        #expect(content.pieces == content.blocks.map(MarkdownContent.Piece.init))
    }

    @Test func everyKindOfBlockBecomesThePieceThatDrawsIt() throws {
        let pieces = MarkdownContent(Self.document).pieces
        let url = try #require(URL(string: "https://example.com/chart.png"))
        #expect(pieces.count == 13)
        #expect(try pieces[0] == .heading(1, styled("Tides")))
        #expect(try pieces[1] == .paragraph(styled("The sea rises and falls **twice a day**, as `high` and *low* water. See [the table](https://example.com/t).")))
        #expect(try pieces[2] == .numbered(4, styled("The Moon pulls the water nearest to it.")))
        #expect(try pieces[3] == .numbered(5, styled("A second bulge forms on the far side.")))
        #expect(try pieces[4] == .bullet(styled("with a point **inside**")))
        #expect(try pieces[5] == .quote([.paragraph(styled("The Sun does the same.")), .bullet(styled("at half the strength"))]))
        #expect(try pieces[6] == .bullet(styled("Spring tides")))
        #expect(try pieces[7] == .bullet(styled("Neap tides")))
        #expect(pieces[8] == .code("let period = 12.42"))
        #expect(pieces[9] == .image(url))
        #expect(pieces[11] == .rule)
        #expect(try pieces[12] == .paragraph(styled("The end.")))
        guard case .code = pieces[10] else {
            Issue.record("a table is drawn as code")
            return
        }
    }

    @Test func aPictureThatIsNotFetchedIsALinkToItsAddress() throws {
        let url = try #require(URL(string: "https://example.com/chart.png?q=the+question"))
        let link = MarkdownContent.link(to: url)
        #expect(String(link.characters) == url.absoluteString)
        #expect(link.runs.allSatisfy { $0.link == url })
    }

    @Test func inlineStylingIsWorkedOutInThePiece() {
        guard case let .paragraph(text) = MarkdownContent("some **bold** text").pieces.first else {
            Issue.record("a paragraph was expected")
            return
        }
        #expect(String(text.characters) == "some bold text")
        #expect(text.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    @Test func aGrowingTextParsedOnTopOfTheLastResultIsTheSameAsParsedAfresh() {
        var content = MarkdownContent.empty
        var text = ""
        var rest = Substring(Self.document)
        while !rest.isEmpty {
            text += rest.prefix(7)
            rest = rest.dropFirst(7)
            content = MarkdownContent(text, reusing: content)
            #expect(content == MarkdownContent(text), "after \(text.count) characters")
        }
        #expect(content.text == Self.document)
    }

    @Test func aTextThatWasRewrittenReusesNothingThatChanged() {
        let first = MarkdownContent("# One\n\nSame.\n\nOld end.")
        let second = MarkdownContent("# Two\n\nSame.\n\nNew end, and longer.\n\n- more", reusing: first)
        #expect(second == MarkdownContent("# Two\n\nSame.\n\nNew end, and longer.\n\n- more"))
    }

    @Test func parsingAwayFromTheCallerGivesTheSameContent() async {
        let content = await MarkdownContent.parsed(Self.document, reusing: .empty)
        #expect(content == MarkdownContent(Self.document))
    }

    @Test func theMemoParsesATextOnceHoweverOftenItIsAskedFor() {
        var parsed: [String] = []
        let memo = MarkdownMemo { text in
            parsed.append(text)
            return MarkdownContent(text)
        }
        for _ in 0 ..< 20 {
            #expect(memo.content(for: "# One") == MarkdownContent("# One"))
        }
        #expect(parsed == ["# One"])
        #expect(memo.content(for: "# Two").blocks == [.heading(1, "Two")])
        #expect(memo.content(for: "# Two").blocks == [.heading(1, "Two")])
        #expect(parsed == ["# One", "# Two"])
    }
}
