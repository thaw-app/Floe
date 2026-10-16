//
//  IconThumbnails.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ImageIO
import Synchronization

/// What an icon's thumbnail is made from.
nonisolated enum IconSource: Hashable {
    /// The icon Finder shows for a file, a folder or a bundle.
    case workspace(path: String)
    /// An image file, such as one in an extension's assets.
    case file(path: String)
    /// A `data:` URI, as extensions pass for images they build themselves.
    case data(uri: String)
}

/// One thumbnail: the same icon at another size or on another display is another bitmap.
nonisolated struct IconKey: Hashable {
    let source: IconSource
    let points: CGFloat
    let scale: CGFloat

    /// The side of the square the icon is drawn in, in device pixels.
    var pixels: Int {
        max(1, Int((points * scale).rounded()))
    }

    var cacheKey: String {
        let origin = switch source {
        case let .workspace(path): "workspace:\(path)"
        case let .file(path): "file:\(path)"
        case let .data(uri): uri
        }
        return "\(points)@\(scale)|\(origin)"
    }
}

/// A thumbnail a view loaded, with the key it was loaded for: a reused view must not show another row's icon.
nonisolated struct LoadedIcon {
    let key: IconKey
    let image: CGImage

    func image(for wanted: IconKey) -> CGImage? {
        key == wanted ? image : nil
    }
}

/// A kept thumbnail, with what it costs and when it was last used.
private nonisolated struct KeptIcon {
    let image: CGImage
    let cost: Int
    var used: UInt64
}

/// Every icon the launcher and Settings draw, kept as the bitmap that reaches the screen and nothing larger.
final nonisolated class IconThumbnailCache: Sendable {
    static let shared = IconThumbnailCache()

    /// A 24 pt row icon at 2x is 9 KB, so the whole catalog (about 300 icons) fits in 3 MB; the rest
    /// covers the Settings sizes, a second display's scale and a few dozen 96 pt file previews at 147 KB.
    static let defaultBudget = 8 * 1024 * 1024

    /// The thumbnails kept. The one used longest ago goes first, and only once the budget is spent: NSCache
    /// may drop an entry whenever it likes, so a row could draw its icon twice.
    private struct Kept {
        let budget: Int
        var entries: [String: KeptIcon] = [:]
        var total = 0
        var clock: UInt64 = 0

        mutating func image(for key: String) -> CGImage? {
            clock += 1
            entries[key]?.used = clock
            return entries[key]?.image
        }

        mutating func store(_ image: CGImage, cost: Int, for key: String) {
            clock += 1
            let replaced = entries.updateValue(KeptIcon(image: image, cost: cost, used: clock), forKey: key)
            total += cost - (replaced?.cost ?? 0)
            while total > budget, let oldest = entries.min(by: { $0.value.used < $1.value.used }) {
                entries[oldest.key] = nil
                total -= oldest.value.cost
            }
        }
    }

    private let kept: Mutex<Kept>
    private let render: @Sendable (IconKey) -> CGImage?

    init(budget: Int = IconThumbnailCache.defaultBudget, render: @escaping @Sendable (IconKey) -> CGImage? = { IconThumbnail.render($0) }) {
        kept = Mutex(Kept(budget: budget))
        self.render = render
    }

    /// The bytes a thumbnail's bitmap takes, which is what the budget counts.
    static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }

    func image(for key: IconKey) -> CGImage? {
        kept.withLock { $0.image(for: key.cacheKey) }
    }

    func store(_ image: CGImage, for key: IconKey) {
        let cost = Self.cost(of: image)
        kept.withLock { $0.store(image, cost: cost, for: key.cacheKey) }
    }

    /// For what is drawn in one pass and never again: a menu bar image, a diagnostic.
    func imageRenderingNow(for key: IconKey) -> CGImage? {
        if let cached = image(for: key) {
            return cached
        }
        guard let image = render(key) else { return nil }
        store(image, for: key)
        return image
    }

    /// Renders off the main thread. A row that scrolled away before its turn costs nothing.
    @concurrent
    func load(_ key: IconKey) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return imageRenderingNow(for: key)
    }
}

/// Makes the bitmap for one key. Nothing here touches the main thread.
nonisolated enum IconThumbnail {
    private static let vectorTypes: Set = ["public.svg-image", "com.adobe.pdf"]

    static func render(_ key: IconKey) -> CGImage? {
        switch key.source {
        case let .workspace(path):
            return draw(NSWorkspace.shared.icon(forFile: path), width: key.pixels, height: key.pixels, scale: key.scale)
        case let .file(path):
            let url = URL(fileURLWithPath: path)
            let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            return source.flatMap { downsampled($0, pixels: key.pixels) } ?? NSImage(contentsOf: url).flatMap { drawn($0, pixels: key.pixels) }
        case let .data(uri):
            guard let data = data(fromURI: uri) else { return nil }
            let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            return source.flatMap { downsampled($0, pixels: key.pixels) } ?? NSImage(data: data).flatMap { drawn($0, pixels: key.pixels) }
        }
    }

    static func data(fromURI uri: String) -> Data? {
        guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
        let payload = String(uri[uri.index(after: comma)...])
        return uri[..<comma].contains(";base64") ? Data(base64Encoded: payload) : (payload.removingPercentEncoding ?? payload).data(using: .utf8)
    }

    /// ImageIO decodes at a reduced size, so a 1024 px asset never exists in memory at full size.
    /// The shorter side ends at `pixels`, since the icon fills its square; nothing is scaled up.
    private static func downsampled(_ source: CGImageSource, pixels: Int) -> CGImage? {
        // A vector file has no pixels to pick from: it is drawn at the size wanted instead.
        if let type = CGImageSourceGetType(source) as String?, vectorTypes.contains(type) {
            return nil
        }
        // An .icns holds one image per size; the largest downsamples best.
        let sizes = (0 ..< CGImageSourceGetCount(source)).map { index -> (width: Int, height: Int) in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            return (properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        }
        guard let best = sizes.indices.max(by: { sizes[$0].width < sizes[$1].width }) else { return nil }
        let longer = max(sizes[best].width, sizes[best].height)
        let shorter = min(sizes[best].width, sizes[best].height)
        guard shorter > 0 else { return nil }
        // Twice the size wanted: the last halving is drawn at high quality, which ImageIO's own scaling is not.
        let wanted = Int((Double(pixels * 2) * Double(longer) / Double(shorter)).rounded(.up))
        guard let decoded = source.thumbnail(at: best, maxPixelSize: min(longer, wanted)) else { return nil }
        let factor = min(1, CGFloat(pixels) / CGFloat(min(decoded.width, decoded.height)))
        let width = max(1, Int((CGFloat(decoded.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(decoded.height) * factor).rounded()))
        // Drawn even at its own size, so every thumbnail is sRGB whatever profile the file carries.
        return bitmap(width: width, height: height) { $0.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height)) }
    }

    /// For what ImageIO does not downsample, SVG above all: drawn so its shorter side is `pixels`.
    private static func drawn(_ image: NSImage, pixels: Int) -> CGImage? {
        let shorter = min(image.size.width, image.size.height)
        guard shorter > 0 else { return nil }
        let factor = CGFloat(pixels) / shorter
        return draw(image, width: Int((image.size.width * factor).rounded()), height: Int((image.size.height * factor).rounded()), scale: factor)
    }

    /// The context is scaled, so a workspace icon picks the artwork it has for this point size on this display.
    private static func draw(_ image: NSImage, width: Int, height: Int, scale: CGFloat) -> CGImage? {
        guard scale > 0 else { return nil }
        return bitmap(width: width, height: height) { context in
            context.scaleBy(x: scale, y: scale)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale))
        }
    }

    private static func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard width > 0, height > 0, let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        else { return nil }
        context.interpolationQuality = .high
        draw(context)
        return context.makeImage()
    }
}

nonisolated extension CGImageSource {
    /// A decode scaled to `maxPixelSize`. ShouldCacheImmediately would keep every decoded image for as long
    /// as the process runs, even with caching off.
    static func thumbnailOptions(maxPixelSize: Int) -> [CFString: Any] {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
    }

    func thumbnail(at index: Int, maxPixelSize: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(self, index, Self.thumbnailOptions(maxPixelSize: maxPixelSize) as CFDictionary)
    }
}
