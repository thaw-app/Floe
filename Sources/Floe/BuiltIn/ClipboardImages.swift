//
//  ClipboardImages.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

extension ClipboardHistoryStore {
    /// The PNG stored for a copied image, or nil when the data is not an image.
    @Sendable static nonisolated func storedPNG(_ data: Data) -> Data? {
        downsampledPNG(data) ?? NSImage(data: data).flatMap(downscaledPNG)
    }

    /// ImageIO scales while it decodes, so the copied image never exists at full size. Drawn through
    /// AppKit, each one left a full-size bitmap in the system's caches. Nil for what ImageIO cannot read.
    static nonisolated func downsampledPNG(_ data: Data) -> Data? {
        let png = NSMutableData()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = source.thumbnail(at: 0, maxPixelSize: Int(imageMaxDimension)),
              let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : nil
    }

    /// For what only AppKit reads, a PDF above all: scales an image to at most imageMaxDimension on its longer side.
    static nonisolated func downscaledPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let longest = max(width, height)
        if longest <= Int(imageMaxDimension), let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        let scale = imageMaxDimension / CGFloat(longest)
        let size = NSSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        scaled.unlockFocus()
        guard let scaledTIFF = scaled.tiffRepresentation,
              let scaledRep = NSBitmapImageRep(data: scaledTIFF)
        else { return nil }
        return scaledRep.representation(using: .png, properties: [:])
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let name = entry.imageFile else { return nil }
        return NSImage(contentsOf: files.directory.appendingPathComponent(name))
    }
}
