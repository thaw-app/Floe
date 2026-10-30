//
//  MarkdownStyling.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// How large the editor sets a note: a document's size in the panel, a smaller one in the floating note.
struct MarkdownEditorStyle: Equatable {
    var body: CGFloat
    /// The note's first line, which is its title.
    var title: CGFloat
    var lineHeight: CGFloat
    /// Room around the text.
    var inset: NSSize
    /// How far each level of a list sits in from the one above it.
    var listIndent: CGFloat

    static let page = MarkdownEditorStyle(body: 15, title: 30, lineHeight: 1.45, inset: NSSize(width: 40, height: 22), listIndent: 24)
    static let compact = MarkdownEditorStyle(body: 14, title: 22, lineHeight: 1.4, inset: NSSize(width: 20, height: 14), listIndent: 22)

    func headingSize(level: Int) -> CGFloat {
        switch level {
        case 1: (body * 1.6).rounded()
        case 2: (body * 1.35).rounded()
        default: (body * 1.15).rounded()
        }
    }
}

nonisolated extension NSAttributedString.Key {
    /// On a task's first word: a box to draw in the margin before it. The value is whether the task is done.
    static let noteTask = NSAttributedString.Key("floe.noteTask")
    /// On a list item's first word: a bullet to draw in the margin before it.
    static let noteBullet = NSAttributedString.Key("floe.noteBullet")
    /// A `---` line, drawn as a rule across the page.
    static let noteRule = NSAttributedString.Key("floe.noteRule")
    /// A quoted line, with a bar beside it.
    static let noteQuote = NSAttributedString.Key("floe.noteQuote")
    /// A line of a fenced code block, on a tinted ground.
    static let noteCode = NSAttributedString.Key("floe.noteCode")
    /// Inline code, on a small rounded ground of its own.
    static let noteInlineCode = NSAttributedString.Key("floe.noteInlineCode")
}

/// Sets a note's Markdown as a document reads, with its marks hidden and lists hanging from drawn bullets and boxes.
/// The text is never changed, only how it is drawn.
enum MarkdownStyler {
    private static let heading = try? NSRegularExpression(pattern: #"^[ \t]*(#{1,6})[ \t]+"#)
    private static let task = try? NSRegularExpression(pattern: #"^([ \t]*)[-*+] \[([ xX])\][ \t]?"#)
    private static let bullet = try? NSRegularExpression(pattern: #"^([ \t]*)[-*+][ \t]+"#)
    private static let number = try? NSRegularExpression(pattern: #"^([ \t]*)(\d+\.)[ \t]+"#)
    private static let quote = try? NSRegularExpression(pattern: #"^[ \t]*>[ \t]?"#)
    private static let rule = try? NSRegularExpression(pattern: #"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let code = try? NSRegularExpression(pattern: #"(`)([^`\n]+)(`)"#)
    // Emphasis is looked for no further than a few hundred characters from where it opens, and a link's label holds
    // no bracket: unbounded, a long line of marks that never close is read again from each one, while the note is typed.
    private static let strong = try? NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.{1,300}?)(?<=\S)(\1)"#)
    private static let emphasis = try? NSRegularExpression(pattern: #"(?<![*_\w])([*_])(?=\S)(.{1,300}?)(?<=\S)(\1)(?![*_\w])"#)
    private static let link = try? NSRegularExpression(pattern: #"(\[)([^\[\]\n]+)(\]\(([^)\s]+)\))"#)
    private static let url = try? NSRegularExpression(pattern: #"(?<![(\[])\bhttps?://[^\s)\]]+"#)

    static func paragraph(_ style: MarkdownEditorStyle) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.lineHeight
        paragraph.paragraphSpacing = style.body * 0.5
        return paragraph
    }

    static func bodyAttributes(_ style: MarkdownEditorStyle) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: style.body), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph(style)]
    }

    static func style(_ storage: NSTextStorage, as style: MarkdownEditorStyle, titleIsFirstLine: Bool) {
        let text = storage.string as NSString
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(bodyAttributes(style), range: NSRange(location: 0, length: text.length))
        var isInCode = false
        var hasTitle = false
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, range, enclosing, _ in
            let line = Line(range: range, content: text.substring(with: range), storage: storage)
            let trimmed = line.content.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                isInCode.toggle()
                storage.addAttributes([.font: mono(style), .foregroundColor: NSColor.tertiaryLabelColor, .noteCode: true], range: enclosing)
                return
            }
            if isInCode {
                storage.addAttributes([.font: mono(style), .noteCode: true], range: enclosing)
                return
            }
            if !hasTitle, !trimmed.isEmpty {
                hasTitle = true
                let mark = line.match(heading)
                if titleIsFirstLine || mark?.range(at: 1).length == 1 {
                    styleTitle(line, mark: mark, as: style)
                    return
                }
            }
            styleBlock(line, as: style)
            styleInline(line, as: style)
        }
    }

    /// One line of the note and where it sits in the whole.
    private struct Line {
        let range: NSRange
        let content: String
        let storage: NSTextStorage

        func match(_ expression: NSRegularExpression?) -> NSTextCheckingResult? {
            expression?.firstMatch(in: content, range: NSRange(location: 0, length: range.length))
        }

        func matches(_ expression: NSRegularExpression?) -> [NSTextCheckingResult] {
            expression?.matches(in: content, range: NSRange(location: 0, length: range.length)) ?? []
        }

        func absolute(_ part: NSRange) -> NSRange {
            NSRange(location: range.location + part.location, length: part.length)
        }

        /// Too small to take room, and clear: the line reads as if the mark were not there.
        func hide(_ part: NSRange) {
            guard part.length > 0, part.location != NSNotFound else { return }
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear], range: absolute(part))
        }

        /// The first character after the line's mark, for what is drawn in the margin before it. Nil on an empty item.
        func firstWord(after mark: NSRange) -> NSRange? {
            mark.upperBound < range.length ? absolute(NSRange(location: mark.upperBound, length: 1)) : nil
        }

        /// How deep in a list the line sits, from the indent before its mark.
        func depth(of indent: NSRange) -> CGFloat {
            let spaces = (content as NSString).substring(with: indent).reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            return CGFloat(spaces / 2)
        }
    }

    private static func styleTitle(_ line: Line, mark: NSTextCheckingResult?, as style: MarkdownEditorStyle) {
        let paragraph = paragraph(style)
        paragraph.lineHeightMultiple = 1.1
        paragraph.paragraphSpacing = style.body
        line.storage.addAttributes([.font: NSFont.systemFont(ofSize: style.title, weight: .bold), .paragraphStyle: paragraph], range: line.range)
        if let mark {
            line.hide(mark.range)
        }
    }

    private static func styleBlock(_ line: Line, as style: MarkdownEditorStyle) {
        let storage = line.storage
        if let mark = line.match(heading) {
            let paragraph = paragraph(style)
            paragraph.lineHeightMultiple = 1.15
            paragraph.paragraphSpacingBefore = style.body * 1.2
            let size = style.headingSize(level: mark.range(at: 1).length)
            storage.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .semibold), .paragraphStyle: paragraph], range: line.range)
            line.hide(mark.range)
        } else if let mark = line.match(task) {
            let isDone = (line.content as NSString).substring(with: mark.range(at: 2)) != " "
            hang(line, depth: line.depth(of: mark.range(at: 1)), by: style.body * 1.7, as: style)
            line.hide(mark.range)
            if let first = line.firstWord(after: mark.range) {
                storage.addAttribute(.noteTask, value: isDone, range: first)
            }
            if isDone {
                let rest = NSRange(location: line.range.location + mark.range.upperBound, length: line.range.length - mark.range.upperBound)
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor], range: rest)
            }
        } else if line.match(rule) != nil {
            storage.addAttributes([.foregroundColor: NSColor.clear, .noteRule: true], range: line.range)
        } else if let mark = line.match(bullet) {
            hang(line, depth: line.depth(of: mark.range(at: 1)), by: style.body * 1.3, as: style)
            line.hide(mark.range)
            if let first = line.firstWord(after: mark.range) {
                storage.addAttribute(.noteBullet, value: true, range: first)
            }
        } else if let mark = line.match(number) {
            // A number is read, so it stays; it hangs like a bullet and lines up the item's wrapped lines.
            let label = (line.content as NSString).substring(with: mark.range(at: 2)) + " "
            let width = (label as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: style.body, weight: .regular)]).width
            let paragraph = hang(line, depth: line.depth(of: mark.range(at: 1)), by: max(style.body * 1.3, width), as: style)
            paragraph.firstLineHeadIndent = paragraph.headIndent - width
            line.hide(mark.range(at: 1))
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.monospacedDigitSystemFont(ofSize: style.body, weight: .regular)], range: line.absolute(mark.range(at: 2)))
        } else if let mark = line.match(quote) {
            let paragraph = paragraph(style)
            paragraph.firstLineHeadIndent = style.body
            paragraph.headIndent = style.body
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .noteQuote: true, .paragraphStyle: paragraph], range: line.range)
            line.hide(mark.range)
        }
    }

    /// A list item's paragraph: in from the edge by its depth and the room its bullet or box takes, so a wrapped
    /// line lines up with the first.
    @discardableResult
    private static func hang(_ line: Line, depth: CGFloat, by marker: CGFloat, as style: MarkdownEditorStyle) -> NSMutableParagraphStyle {
        let paragraph = paragraph(style)
        paragraph.paragraphSpacing = style.body * 0.25
        paragraph.headIndent = depth * style.listIndent + marker
        paragraph.firstLineHeadIndent = paragraph.headIndent
        line.storage.addAttribute(.paragraphStyle, value: paragraph, range: line.range)
        return paragraph
    }

    private static func styleInline(_ line: Line, as style: MarkdownEditorStyle) {
        let storage = line.storage
        for match in line.matches(strong) {
            storage.applyFontTraits(.boldFontMask, range: line.absolute(match.range))
            line.hide(match.range(at: 1))
            line.hide(match.range(at: 3))
        }
        for match in line.matches(emphasis) {
            storage.applyFontTraits(.italicFontMask, range: line.absolute(match.range))
            line.hide(match.range(at: 1))
            line.hide(match.range(at: 3))
        }
        for match in line.matches(link) {
            if let url = URL(string: (line.content as NSString).substring(with: match.range(at: 4))) {
                storage.addAttribute(.link, value: url, range: line.absolute(match.range(at: 2)))
            }
            line.hide(match.range(at: 1))
            line.hide(match.range(at: 3))
        }
        for match in line.matches(url) {
            if let address = URL(string: (line.content as NSString).substring(with: match.range)) {
                storage.addAttribute(.link, value: address, range: line.absolute(match.range))
            }
        }
        // Last, so code keeps its own font over any emphasis inside it.
        for match in line.matches(code) {
            storage.addAttributes([.font: mono(style), .noteInlineCode: true], range: line.absolute(match.range(at: 2)))
            line.hide(match.range(at: 1))
            line.hide(match.range(at: 3))
        }
    }

    private static func mono(_ style: MarkdownEditorStyle) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: style.body - 1, weight: .regular)
    }
}

/// What the editor's own keys and its bar do to the text, as plain functions of it.
enum MarkdownEditing {
    /// What Return does on a list's item: start the next, or end the list when the item was left empty.
    enum Continuation: Equatable {
        case next(String)
        /// The empty item's mark, this many UTF-16 units long, goes.
        case end(Int)
    }

    /// What a line can be turned into.
    enum Block: Equatable {
        case body
        case heading(Int)
        case task
        case bullet
        case numbered
    }

    static let indent = "  "

    /// An item's mark: `- [ ] `, `- `, `* ` or `1. `, after any indent.
    private static let item = try? NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+]) \[[ xX]\] |([-*+]) |(\d+)\. )"#)
    /// A mark the editor hides at the start of a line: a heading's, a task's, a bullet's or a quote's.
    private static let hiddenMark = try? NSRegularExpression(pattern: #"^[ \t]*(?:#{1,6}[ \t]+|[-*+] \[[ xX]\][ \t]?|[-*+][ \t]+|>[ \t]?)"#)
    /// Any line's own mark, after any indent.
    private static let blockMark = try? NSRegularExpression(pattern: #"^([ \t]*)(?:#{1,6}[ \t]+|[-*+] \[[ xX]\] |[-*+] |\d+\. |>[ \t]?)?"#)
    /// A task's tick.
    private static let task = try? NSRegularExpression(pattern: #"^[ \t]*[-*+] \[([ xX])\]"#)

    /// The continuation for the text before the caret on its line. Nil when that line is no list's item.
    static func continuation(after line: String) -> Continuation? {
        let text = line as NSString
        guard let match = item?.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return nil }
        if text.substring(from: match.range.upperBound).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .end(match.range.length)
        }
        let indent = text.substring(with: match.range(at: 1))
        if match.range(at: 2).location != NSNotFound {
            return .next(indent + text.substring(with: match.range(at: 2)) + " [ ] ")
        }
        if match.range(at: 3).location != NSNotFound {
            return .next(indent + text.substring(with: match.range(at: 3)) + " ")
        }
        let number = Int(text.substring(with: match.range(at: 4))) ?? 0
        return .next("\(indent)\(number + 1). ")
    }

    /// How long the hidden mark at the start of the line is, in UTF-16 units: where the line's words begin.
    static func hiddenMarkLength(of line: String) -> Int {
        hiddenMark?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range.length ?? 0
    }

    /// The tick of the task on the line, which a click in its box toggles. Nil when the line is no task.
    static func taskTick(inLine line: String) -> NSRange? {
        task?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range(at: 1)
    }

    /// The selection wrapped in the marker, or unwrapped when it already is.
    static func toggleWrap(_ selected: String, with marker: String) -> String {
        if selected.count >= marker.count * 2, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            return String(selected.dropFirst(marker.count).dropLast(marker.count))
        }
        return marker + selected + marker
    }

    /// A link around the selection: an address becomes the link's target, anything else its text.
    static func link(around selected: String) -> (text: String, caret: Int) {
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            return ("[](\(selected))", 1)
        }
        let text = "[\(selected)]()"
        return (text, (text as NSString).length - 1)
    }

    /// The selection with its emphasis, code and link marks taken off.
    static func stripped(_ selected: String) -> String {
        var text = selected.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`", "*", "_"] {
            text = text.replacingOccurrences(of: mark, with: "")
        }
        return text
    }

    /// The line made into another kind of block, its words and indent kept.
    static func line(_ line: String, as block: Block) -> String {
        let text = line as NSString
        let mark = blockMark?.firstMatch(in: line, range: NSRange(location: 0, length: text.length))
        let indent = mark.map { text.substring(with: $0.range(at: 1)) } ?? ""
        let words = text.substring(from: mark?.range.upperBound ?? 0)
        let prefix = switch block {
        case .body: ""
        case let .heading(level): String(repeating: "#", count: level) + " "
        case .task: "- [ ] "
        case .bullet: "- "
        case .numbered: "1. "
        }
        return indent + prefix + words
    }
}
