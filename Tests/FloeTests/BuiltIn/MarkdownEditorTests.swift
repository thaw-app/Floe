//
//  MarkdownEditorTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import SwiftUI
import Testing

@MainActor struct MarkdownEditorTests {
    // MARK: The keys

    @Test func returnCarriesAListOnAndEndsItOnAnEmptyItem() {
        #expect(MarkdownEditing.continuation(after: "- milk") == .next("- "))
        #expect(MarkdownEditing.continuation(after: "  * [x] eggs") == .next("  * [ ] "), "a new task starts open")
        #expect(MarkdownEditing.continuation(after: "9. ninth") == .next("10. "))
        #expect(MarkdownEditing.continuation(after: "- ") == .end(2))
        #expect(MarkdownEditing.continuation(after: "  - [ ] ") == .end(8))
        #expect(MarkdownEditing.continuation(after: "plain words") == nil)
        #expect(MarkdownEditing.continuation(after: "-not a list") == nil)
    }

    @Test func theHiddenMarkIsWhereALinesWordsBegin() {
        #expect(MarkdownEditing.hiddenMarkLength(of: "## Plan") == 3)
        #expect(MarkdownEditing.hiddenMarkLength(of: "  - [ ] milk") == 8)
        #expect(MarkdownEditing.hiddenMarkLength(of: "- milk") == 2)
        #expect(MarkdownEditing.hiddenMarkLength(of: "> quoted") == 2)
        #expect(MarkdownEditing.hiddenMarkLength(of: "1. first") == 0, "a list's number stays in sight")
        #expect(MarkdownEditing.hiddenMarkLength(of: "plain") == 0)
        #expect(MarkdownEditing.taskTick(inLine: "- [x] bread") == NSRange(location: 3, length: 1))
        #expect(MarkdownEditing.taskTick(inLine: "- bread") == nil)
    }

    @Test func formattingKeysWrapAndUnwrap() {
        #expect(MarkdownEditing.toggleWrap("word", with: "**") == "**word**")
        #expect(MarkdownEditing.toggleWrap("**word**", with: "**") == "word")
        #expect(MarkdownEditing.toggleWrap("", with: "_") == "__")
        #expect(MarkdownEditing.link(around: "Floe") == ("[Floe]()", 7))
        #expect(MarkdownEditing.link(around: "https://floe.app") == ("[](https://floe.app)", 1))
        #expect(MarkdownEditing.stripped("**bold** and _it_ with `code` and [a link](https://floe.app)") == "bold and it with code and a link")
    }

    @Test func aLineTurnsIntoAnyBlockAndKeepsItsWords() {
        #expect(MarkdownEditing.line("## Plan", as: .heading(1)) == "# Plan")
        #expect(MarkdownEditing.line("- [x] ship", as: .bullet) == "- ship")
        #expect(MarkdownEditing.line("  1. first", as: .task) == "  - [ ] first", "the indent stays")
        #expect(MarkdownEditing.line("> quoted", as: .body) == "quoted")
        #expect(MarkdownEditing.line("plain", as: .numbered) == "1. plain")
    }

    // MARK: How it reads

    private func styled(_ text: String, titleIsFirstLine: Bool = false) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler.style(storage, as: .page, titleIsFirstLine: titleIsFirstLine)
        return storage
    }

    private func font(_ storage: NSTextStorage, at index: Int) -> NSFont? {
        storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func at(_ word: String, in text: String) -> Int {
        (text as NSString).range(of: word).location
    }

    @Test func noMarkIsInSightAndTheTextIsNeverChanged() {
        let text = "# Plan\nsome **bold** and `code` words"
        let storage = styled(text)
        #expect((font(storage, at: 0)?.pointSize ?? 99) < 1, "the title's # is hidden")
        #expect(font(storage, at: 2)?.pointSize == MarkdownEditorStyle.page.title)
        let star = at("**", in: text)
        #expect((font(storage, at: star)?.pointSize ?? 99) < 1)
        #expect(font(storage, at: star + 2)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect((font(storage, at: at("`", in: text))?.pointSize ?? 99) < 1)
        #expect(storage.attribute(.noteInlineCode, at: at("code", in: text), effectiveRange: nil) != nil)
        #expect(storage.string == text)
    }

    @Test func listsHangFromBulletsAndBoxesDrawnInTheirMargin() {
        let text = "Note\n- [ ] milk\n- [x] bread\n- loose\n  - nested\n---"
        let storage = styled(text)
        #expect(storage.attribute(.noteTask, at: at("milk", in: text), effectiveRange: nil) as? Bool == false)
        #expect(storage.attribute(.noteTask, at: at("bread", in: text), effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.strikethroughStyle, at: at("bread", in: text), effectiveRange: nil) != nil)
        #expect(storage.attribute(.noteBullet, at: at("loose", in: text), effectiveRange: nil) != nil)
        #expect(storage.attribute(.noteRule, at: at("---", in: text), effectiveRange: nil) != nil)
        let item = storage.attribute(.paragraphStyle, at: at("loose", in: text), effectiveRange: nil) as? NSParagraphStyle
        let nested = storage.attribute(.paragraphStyle, at: at("nested", in: text), effectiveRange: nil) as? NSParagraphStyle
        #expect((item?.headIndent ?? 0) > 0, "wrapped lines line up with the words, not the bullet")
        #expect((nested?.headIndent ?? 0) > (item?.headIndent ?? 0))
    }

    @Test func appleNotesTitleIsItsFirstLineWithoutAHash() {
        #expect(font(styled("Groceries\nmilk", titleIsFirstLine: true), at: 0)?.pointSize == MarkdownEditorStyle.page.title)
        #expect(font(styled("Groceries\nmilk"), at: 0)?.pointSize == MarkdownEditorStyle.page.body, "a folder's note needs its #")
    }

    @Test func insideCodeNothingIsStyledAsMarkdown() {
        let text = "Note\n```\n# not a heading\n- [ ] not a task\n```"
        let storage = styled(text)
        #expect(storage.attribute(.noteTask, at: at("not a task", in: text), effectiveRange: nil) == nil)
        #expect(storage.attribute(.noteCode, at: at("# not", in: text), effectiveRange: nil) != nil)
    }

    @Test func aPlainFolderShowsItsOwnIcon() {
        let folder = FileManager.default.temporaryDirectory
        #expect(FolderNoteStore(folder: folder).placeIcon == folder.path)
        #expect(FolderNoteStore(folder: nil).placeIcon == nil)
    }
}

/// The editor in a real window, as the note views show it.
@MainActor struct MarkdownEditorViewTests {
    @Test func theEditorFillsItsWindowAndTakesTyping() throws {
        final class Box {
            var text = "# Plan\n"
        }
        let box = Box()
        let editor = MarkdownEditor(text: Binding(get: { box.text }, set: { box.text = $0 }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        // Closed below and also released by the test: a window made here must not free itself on close too.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: editor.frame(width: 420, height: 300))
        window.contentView?.layoutSubtreeIfNeeded()
        let textView = try #require(Self.find(NoteTextView.self, in: window.contentView))
        #expect(textView.frame.width > 400, "a text view left at zero width has nowhere to type")
        #expect(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText("milk", replacementRange: textView.selectedRange())
        #expect(box.text == "# Plan\nmilk")
        window.close()
    }

    @Test func theCaretSkipsAHiddenMarkAndBackspaceTakesItOff() throws {
        final class Box {
            var text = "Note\n- milk"
        }
        let box = Box()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MarkdownEditor(text: Binding(get: { box.text }, set: { box.text = $0 })).frame(width: 420, height: 300))
        window.contentView?.layoutSubtreeIfNeeded()
        let textView = try #require(Self.find(NoteTextView.self, in: window.contentView))
        #expect(window.makeFirstResponder(textView))
        let item = (box.text as NSString).range(of: "- milk").location
        textView.setSelectedRange(NSRange(location: item, length: 0))
        #expect(textView.selectedRange().location == item + 2, "typing lands in the words, not before the -")
        textView.deleteBackward(nil)
        #expect(box.text == "Note\nmilk", "Backspace at the words' start makes the item body text")
        window.close()
    }

    @Test func returnCarriesTheListOnAndReturnOnAnEmptyItemEndsIt() {
        let textView = Self.editing("- milk", caretAt: 6)
        textView.insertNewline(nil)
        #expect(textView.string == "- milk\n- ")
        textView.insertNewline(nil)
        #expect(textView.string == "- milk\n", "the empty item's mark goes and the list ends")
        textView.insertText("plain", replacementRange: textView.selectedRange())
        textView.insertNewline(nil)
        #expect(textView.string == "- milk\nplain\n", "a body line takes a plain Return")
    }

    @Test func tabNestsAnItemAndShiftTabTakesItBack() {
        let textView = Self.editing("- milk", caretAt: 6)
        textView.insertTab(nil)
        #expect(textView.string == MarkdownEditing.indent + "- milk")
        textView.insertBacktab(nil)
        #expect(textView.string == "- milk")
        textView.insertBacktab(nil)
        #expect(textView.string == "- milk", "an item at the margin stays there")
    }

    @Test func theFormatCommandsChangeTheSelectionAndPlaceTheCaret() {
        let textView = Self.editing("milk", caretAt: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.run(.bold)
        #expect(textView.string == "**milk**")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 8), "the wrapped words stay selected")
        textView.run(.plain)
        #expect(textView.string == "milk")
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.run(.italic)
        #expect(textView.string == "milk__")
        #expect(textView.selectedRange() == NSRange(location: 5, length: 0), "with nothing selected the caret goes between the marks")
        textView.string = "Floe"
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.run(.link)
        #expect(textView.string == "[Floe]()")
        #expect(textView.selectedRange() == NSRange(location: 7, length: 0), "the caret waits where the address goes")
        textView.string = "milk"
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.run(.duplicate)
        #expect(textView.string == "milk\nmilk")
    }

    @Test func aBlockCommandMakesOverEverySelectedLine() {
        let textView = Self.editing("milk\neggs", caretAt: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 9))
        textView.run(.block(.task))
        #expect(textView.string == "- [ ] milk\n- [ ] eggs")
        #expect(textView.selectedRange() == NSRange(location: 21, length: 0), "the caret ends after the last line's words")
        textView.run(.block(.heading(2)))
        #expect(textView.string == "- [ ] milk\n## eggs", "only the caret's line changes once the selection is gone")
    }

    @Test func aNoteThatCannotBeWrittenTakesNoCommand() {
        let textView = Self.editing("milk", caretAt: 0)
        textView.isEditable = false
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.run(.bold)
        #expect(textView.string == "milk")
    }

    @Test func commandKeysFormatAndOptionCommandNumbersSetTheLine() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let textView = Self.editing("milk", caretAt: 0)
        window.contentView = textView
        #expect(window.makeFirstResponder(textView))
        func press(_ key: String, _ flags: NSEvent.ModifierFlags) throws -> Bool {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0
            ))
            return textView.performKeyEquivalent(with: event)
        }
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        #expect(try press("b", .command))
        #expect(textView.string == "**milk**")
        #expect(try press("1", [.command, .option]))
        #expect(textView.string == "# **milk**")
        #expect(try !press("b", [.command, .shift]), "a key Floe does not use is left to the menus")
        window.close()
    }

    /// A text view on its own, holding `text` with the caret at `caret`.
    private static func editing(_ text: String, caretAt caret: Int) -> NoteTextView {
        let textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return textView
    }

    private static func find<T: NSView>(_: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let found = view as? T {
            return found
        }
        return view.subviews.lazy.compactMap { find(T.self, in: $0) }.first
    }
}
