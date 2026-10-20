//
//  MarkdownEditor.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// A note written as Markdown and shown as the document it makes, the file kept as plain text. Its keys are listed
/// in `NoteTextView.commandKeys` and `blockKeys`.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var style = MarkdownEditorStyle.page
    /// Apple Notes names a note by its first line, so that line is the title with or without a `#`.
    var titleIsFirstLine = false
    var isEditable = true
    /// Changing it puts the caret in the editor.
    var focusToken = 0
    /// For a bar of buttons that does what the keys do.
    var commands: MarkdownEditorCommands?
    var onFocusChange: (Bool) -> Void = { _ in
        // Nobody asked.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Any size to start with: the text view takes the scroll view's, and its width follows from then on. One
        // made at zero stays zero wide, with nowhere to click or type.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let container = NSTextContainer(size: NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        let layout = NoteLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        let textView = NoteTextView(frame: NSRect(origin: .zero, size: scroll.contentSize), textContainer: container)
        textView.storage = storage
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // Markdown's quotes, dashes and asterisks are marks, not typography to improve.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        textView.delegate = context.coordinator
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.onFocusChange(focused)
        }
        textView.string = text
        commands?.textView = textView

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        context.coordinator.restyle(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let restyles = coordinator.parent.style != style || coordinator.parent.titleIsFirstLine != titleIsFirstLine
        coordinator.parent = self
        guard let textView = scroll.documentView as? NoteTextView else { return }
        commands?.textView = textView
        textView.isEditable = isEditable
        if textView.string != text {
            // Another note, or what another app wrote: the caret stays where it was as far as the text allows.
            let caret = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(caret.location, (text as NSString).length), length: 0))
            coordinator.restyle(textView)
        } else if restyles {
            coordinator.restyle(textView)
        }
        if focusToken != coordinator.focusToken {
            coordinator.focusToken = focusToken
            Task { @MainActor in textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var focusToken: Int
        /// Where the caret was, to tell a step left out of a line from a click into its hidden mark.
        private var lastCaret = 0
        private var isMovingCaret = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            focusToken = parent.focusToken
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            restyle(textView)
        }

        /// Keeps the caret out of a line's hidden mark, so what is typed lands in the words and not before a `#`.
        /// A step left from the words goes on to the line above.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isMovingCaret else { return }
            let selection = textView.selectedRange()
            defer { lastCaret = textView.selectedRange().location }
            guard selection.length == 0 else { return }
            let text = textView.string as NSString
            let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
            let words = line.location + MarkdownEditing.hiddenMarkLength(of: text.substring(with: line))
            guard selection.location < words else { return }
            let target = lastCaret == words && line.location > 0 ? line.location - 1 : words
            isMovingCaret = true
            textView.setSelectedRange(NSRange(location: target, length: 0))
            isMovingCaret = false
        }

        func restyle(_ textView: NSTextView) {
            textView.textContainerInset = parent.style.inset
            // An input method's text in progress is the method's to draw.
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            MarkdownStyler.style(storage, as: parent.style, titleIsFirstLine: parent.titleIsFirstLine)
            textView.typingAttributes = MarkdownStyler.bodyAttributes(parent.style)
        }
    }
}

/// What the formatting bar's buttons do, on the editor they were handed.
final class MarkdownEditorCommands {
    weak var textView: NoteTextView?

    func run(_ command: NoteTextView.Command) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.run(command)
    }
}

/// The text view under the editor: Markdown's keys, a click on a task's box, and Backspace that takes a line's
/// hidden mark off before anything else.
final class NoteTextView: NSTextView {
    enum Command {
        case bold, italic, code, link, plain, duplicate
        case block(MarkdownEditing.Block)
    }

    /// The text the view shows. Built by hand to draw with `NoteLayoutManager`, so nothing else keeps it: a storage
    /// nobody holds is freed at once, and the view is left with no text to show or type into.
    var storage: NSTextStorage?
    var onFocusChange: (Bool) -> Void = { _ in
        // Nobody asked.
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocusChange(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChange(false)
        }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEditable, let tick = tick(clickedAt: point) {
            replace(tick, with: (string as NSString).substring(with: tick) == " " ? "x" : " ")
            return
        }
        super.mouseDown(with: event)
    }

    /// A task's tick when the click is in the margin where its box is drawn.
    private func tick(clickedAt point: NSPoint) -> NSRange? {
        let text = string as NSString
        let index = min(characterIndexForInsertion(at: point), text.length)
        let line = text.lineRange(for: NSRange(location: index, length: 0))
        let content = text.substring(with: line)
        guard let tick = MarkdownEditing.taskTick(inLine: content), let layout = layoutManager, text.length > 0 else { return nil }
        let words = min(line.location + MarkdownEditing.hiddenMarkLength(of: content), text.length - 1)
        let glyph = layout.glyphIndexForCharacter(at: words)
        let start = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + layout.location(forGlyphAt: glyph).x + textContainerOrigin.x
        return point.x < start - 2 ? NSRange(location: line.location + tick.location, length: 1) : nil
    }

    override func deleteBackward(_ sender: Any?) {
        let caret = selectedRange()
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: caret.location, length: 0))
        let mark = MarkdownEditing.hiddenMarkLength(of: text.substring(with: line))
        // At the start of a heading's or an item's words the mark goes first, and the line becomes body text.
        if caret.length == 0, mark > 0, caret.location == line.location + mark {
            replace(NSRange(location: line.location, length: mark), with: "")
            return
        }
        super.deleteBackward(sender)
    }

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let caret = selectedRange()
        let line = text.lineRange(for: NSRange(location: caret.location, length: 0))
        let before = text.substring(with: NSRange(location: line.location, length: caret.location - line.location))
        let after = text.substring(with: NSRange(location: caret.upperBound, length: max(0, line.upperBound - caret.upperBound)))
            .trimmingCharacters(in: .newlines)
        switch MarkdownEditing.continuation(after: before) {
        case let .next(prefix):
            insertText("\n" + prefix, replacementRange: caret)
        case let .end(prefixLength) where after.isEmpty:
            // Return on an empty item ends the list.
            replace(NSRange(location: line.location, length: prefixLength), with: "")
        default:
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        guard let line = listLine() else { return super.insertTab(sender) }
        replace(NSRange(location: line.location, length: 0), with: MarkdownEditing.indent)
    }

    override func insertBacktab(_ sender: Any?) {
        guard let line = listLine() else { return super.insertBacktab(sender) }
        let leading = (string as NSString).substring(with: line).prefix { $0 == " " || $0 == "\t" }
        let removed = leading.hasPrefix("\t") ? 1 : min(leading.count, MarkdownEditing.indent.count)
        if removed > 0 {
            replace(NSRange(location: line.location, length: removed), with: "")
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, isEditable, let key = event.charactersIgnoringModifiers,
              let command = Self.command(for: key, flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        else { return super.performKeyEquivalent(with: event) }
        run(command)
        return true
    }

    /// ⌘ with a letter, and ⌥⌘ with a number for what the line is.
    private static let commandKeys: [String: Command] = ["b": .bold, "i": .italic, "e": .code, "k": .link, "d": .duplicate, "\\": .plain]
    private static let blockKeys: [String: Command] = [
        "0": .block(.body), "1": .block(.heading(1)), "2": .block(.heading(2)), "3": .block(.heading(3)),
        "4": .block(.task), "5": .block(.bullet), "6": .block(.numbered),
    ]

    private static func command(for key: String, flags: NSEvent.ModifierFlags) -> Command? {
        switch flags {
        case .command: commandKeys[key]
        case [.command, .option]: blockKeys[key]
        default: nil
        }
    }

    func run(_ command: Command) {
        guard isEditable else { return }
        let text = string as NSString
        let selection = selectedRange()
        switch command {
        case .bold: wrap(with: "**")
        case .italic: wrap(with: "_")
        case .code: wrap(with: "`")
        case .link:
            let link = MarkdownEditing.link(around: text.substring(with: selection))
            replace(selection, with: link.text)
            setSelectedRange(NSRange(location: selection.location + link.caret, length: 0))
        case .plain:
            replace(selection, with: MarkdownEditing.stripped(text.substring(with: selection)))
        case .duplicate:
            let line = text.lineRange(for: selection)
            let copy = text.substring(with: line)
            replace(NSRange(location: line.upperBound, length: 0), with: copy.hasSuffix("\n") ? copy : "\n" + copy)
        case let .block(block):
            replaceLines { MarkdownEditing.line($0, as: block) }
        }
    }

    /// The line the caret is on, when it is a list's item.
    private func listLine() -> NSRange? {
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        return MarkdownEditing.continuation(after: text.substring(with: line)) == nil ? nil : line
    }

    private func wrap(with marker: String) {
        let selection = selectedRange()
        let wrapped = MarkdownEditing.toggleWrap((string as NSString).substring(with: selection), with: marker)
        replace(selection, with: wrapped)
        // With nothing selected the caret goes between the marks, ready to type.
        if selection.length == 0 {
            setSelectedRange(NSRange(location: selection.location + (marker as NSString).length, length: 0))
        } else {
            setSelectedRange(NSRange(location: selection.location, length: (wrapped as NSString).length))
        }
    }

    /// Each selected line made over, as one change to undo. The caret ends after the last line's words.
    private func replaceLines(_ change: (String) -> String) {
        let text = string as NSString
        let lines = text.lineRange(for: selectedRange())
        let changed = text.substring(with: lines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in line.isEmpty && index > 0 ? "" : change(String(line)) }
            .joined(separator: "\n")
        replace(lines, with: changed)
        setSelectedRange(NSRange(location: lines.location + (changed as NSString).length - (changed.hasSuffix("\n") ? 1 : 0), length: 0))
    }

    /// A change the user can undo, which the editor hears like typing.
    private func replace(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
    }
}
