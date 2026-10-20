//
//  NoteLayoutManager.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Draws what the styler marked in place of the Markdown it hid: bullets and task boxes in a list's margin, rules,
/// a bar beside a quote, and a ground under code.
final nonisolated class NoteLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphs: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphs, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.noteCode, in: characters) { value, range, _ in
            guard value != nil else { return }
            var block = boundingRect(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
            block.origin.x = 0
            block.size.width = container.size.width
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: block.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -8, dy: 0), xRadius: 8, yRadius: 8).fill()
        }
        storage.enumerateAttribute(.noteInlineCode, in: characters) { value, range, _ in
            guard value != nil, let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let span = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let baseline = baselinePoint(ofGlyph: span.location, at: origin)
            let width = boundingRect(forGlyphRange: span, in: container).width
            let chip = NSRect(x: baseline.x - 4, y: baseline.y - font.ascender - 1, width: width + 8, height: font.ascender - font.descender + 2)
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
        }
        storage.enumerateAttribute(.noteQuote, in: characters) { value, range, _ in
            guard value != nil else { return }
            let quote = boundingRect(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: origin.x, y: quote.minY + origin.y, width: 3, height: quote.height), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override func drawGlyphs(forGlyphRange glyphs: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphs, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.noteTask, in: characters) { value, range, _ in
            guard let isDone = value as? Bool, let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let words = baselinePoint(ofGlyph: glyphIndexForCharacter(at: range.location), at: origin)
            let side = (font.pointSize * 1.1).rounded()
            let box = NSRect(x: words.x - font.pointSize * 1.7, y: words.y - font.capHeight / 2 - side / 2, width: side, height: side)
            draw(symbol: isDone ? "checkmark.circle.fill" : "circle", color: isDone ? .controlAccentColor : .tertiaryLabelColor, in: box)
        }
        storage.enumerateAttribute(.noteBullet, in: characters) { value, range, _ in
            guard value != nil, let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let words = baselinePoint(ofGlyph: glyphIndexForCharacter(at: range.location), at: origin)
            let side = (font.pointSize * 0.36).rounded()
            let center = NSPoint(x: words.x - font.pointSize * 0.8, y: words.y - font.xHeight / 2)
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)).fill()
        }
        storage.enumerateAttribute(.noteRule, in: characters) { value, range, _ in
            guard value != nil else { return }
            let line = boundingRect(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
            NSColor.separatorColor.setFill()
            NSRect(x: origin.x, y: (line.midY + origin.y).rounded(), width: container.size.width, height: 1).fill()
        }
    }

    /// Where a glyph sits on its line: its left edge and the line's baseline, in the view's terms.
    private func baselinePoint(ofGlyph glyph: Int, at origin: NSPoint) -> NSPoint {
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = location(forGlyphAt: glyph)
        return NSPoint(x: origin.x + line.minX + location.x, y: origin.y + line.minY + location.y)
    }

    private func draw(symbol: String, color: NSColor, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .regular).applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
