//
//  MenuBarGlyph.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The figure of the app icon for the menu bar: the floe seen from above, with the lead of open water
/// that cuts one corner off. One colour, drawn as a template so the menu bar tints it.
nonisolated enum MenuBarGlyph {
    /// The floe's outline and the lead's middle line, in the 1024 point space of the app icon.
    static let floe: [CGPoint] = [
        CGPoint(x: 265, y: 320), CGPoint(x: 443, y: 237), CGPoint(x: 597, y: 255), CGPoint(x: 666, y: 222), CGPoint(x: 752, y: 354),
        CGPoint(x: 724, y: 481), CGPoint(x: 762, y: 562), CGPoint(x: 656, y: 700), CGPoint(x: 445, y: 721), CGPoint(x: 299, y: 669), CGPoint(x: 234, y: 520),
    ]
    static let lead: [CGPoint] = [CGPoint(x: 499, y: 150), CGPoint(x: 592, y: 476), CGPoint(x: 801, y: 627), CGPoint(x: 1040, y: 800)]
    /// Wider than in the app icon, where it is 40: at menu bar size a thinner lead closes up.
    static let leadWidth: CGFloat = 64

    static func image(side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let bounds = CGRect(x: 234, y: 222, width: 528, height: 499)
            let scale = (side - 2) / max(bounds.width, bounds.height)
            let transform = NSAffineTransform()
            transform.translateX(by: side / 2, yBy: side / 2)
            transform.scale(by: scale)
            transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
            transform.concat()

            let outline = path(through: floe, closed: true)
            // The stroke rounds the corners, as the icon's floe has them.
            outline.lineWidth = 30
            outline.lineJoinStyle = .round
            NSColor.black.setFill()
            NSColor.black.setStroke()
            outline.fill()
            outline.stroke()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let water = path(through: lead, closed: false)
            water.lineWidth = leadWidth
            water.lineJoinStyle = .miter
            water.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Floe"
        return image
    }

    private static func path(through points: [CGPoint], closed: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        if let first = points.first {
            path.move(to: first)
        }
        for point in points.dropFirst() {
            path.line(to: point)
        }
        if closed {
            path.close()
        }
        return path
    }
}
