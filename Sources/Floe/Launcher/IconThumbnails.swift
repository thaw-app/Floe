//
//  IconThumbnails.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import CryptoKit
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
    /// An image on the web, fetched before it is drawn.
    case remote(url: URL)
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
        case let .remote(url): "remote:\(url.absoluteString)"
        // A digest, so the cache does not keep a copy of an image the size of the URI beside its thumbnail.
        case let .data(uri): "data:" + SHA256.hash(data: Data(uri.utf8)).map { String(format: "%02x", $0) }.joined()
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
            guard total > budget else { return }
            // One sort however many go: a batch of large previews can push out dozens at once.
            for (key, icon) in entries.sorted(by: { $0.value.used < $1.value.used }) where total > budget {
                entries[key] = nil
                total -= icon.cost
            }
        }
    }

    private let kept: Mutex<Kept>
    private let render: @Sendable (IconKey) -> CGImage?
    private let fetch: @Sendable (URL) async -> Data?

    init(
        budget: Int = IconThumbnailCache.defaultBudget,
        render: @escaping @Sendable (IconKey) -> CGImage? = { IconThumbnail.render($0) },
        fetch: @escaping @Sendable (URL) async -> Data? = { await RemoteImage.data(at: $0) }
    ) {
        kept = Mutex(Kept(budget: budget))
        self.render = render
        self.fetch = fetch
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

    /// Lets go of every thumbnail, when macOS asks for memory back. The rows draw theirs again as they show.
    func removeAll() {
        kept.withLock { kept in
            kept.entries = [:]
            kept.total = 0
        }
    }

    /// For what is drawn in one pass and never again: a menu bar image, a diagnostic. A remote image is not
    /// fetched here, since that cannot happen in one pass.
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
        guard case let .remote(url) = key.source else { return imageRenderingNow(for: key) }
        if let cached = image(for: key) {
            return cached
        }
        guard let data = await fetch(url), !Task.isCancelled, let image = IconThumbnail.image(from: data, pixels: key.pixels) else { return nil }
        store(image, for: key)
        return image
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
            return thumbnail(of: source, pixels: key.pixels) { NSImage(contentsOf: url) }
        case let .data(uri):
            return data(fromURI: uri).flatMap { image(from: $0, pixels: key.pixels) }
        case .remote:
            return nil
        }
    }

    /// An image file's bytes drawn so the shorter side is `pixels`.
    static func image(from data: Data, pixels: Int) -> CGImage? {
        let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        return thumbnail(of: source, pixels: pixels) { NSImage(data: data) }
    }

    /// What ImageIO made of a file: a thumbnail, a picture too large to decode at all, or nothing it could use.
    enum Downsampled {
        case image(CGImage)
        case tooLarge
        case unusable
    }

    /// The thumbnail ImageIO makes, else the file drawn through NSImage. A picture too large for ImageIO is not
    /// handed to NSImage, which would decode it whole.
    private static func thumbnail(of source: CGImageSource?, pixels: Int, image: () -> NSImage?) -> CGImage? {
        switch source.map({ downsampled($0, pixels: pixels) }) ?? .unusable {
        case let .image(thumbnail): thumbnail
        case .tooLarge: nil
        case .unusable: image().flatMap { drawn($0, pixels: pixels) }
        }
    }

    static func data(fromURI uri: String) -> Data? {
        guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
        let payload = String(uri[uri.index(after: comma)...])
        return uri[..<comma].contains(";base64") ? Data(base64Encoded: payload) : (payload.removingPercentEncoding ?? payload).data(using: .utf8)
    }

    /// ImageIO decodes at a reduced size, so a 1024 px asset never exists in memory at full size.
    /// The shorter side ends at `pixels`, since the icon fills its square, unless that would make the longer side
    /// more than `longestSide` times as long; nothing is scaled up.
    static func downsampled(_ source: CGImageSource, pixels: Int) -> Downsampled {
        // A vector file has no pixels to pick from: it is drawn at the size wanted instead.
        if let type = CGImageSourceGetType(source) as String?, vectorTypes.contains(type) {
            return .unusable
        }
        // An .icns holds one image per size; the largest downsamples best.
        let sizes = (0 ..< CGImageSourceGetCount(source)).map { index -> (width: Int, height: Int) in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            return (properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        }
        guard let best = sizes.indices.max(by: { sizes[$0].width < sizes[$1].width }) else { return .unusable }
        let longer = max(sizes[best].width, sizes[best].height)
        let shorter = min(sizes[best].width, sizes[best].height)
        guard shorter > 0 else { return .unusable }
        guard longer <= maxSourcePixels / shorter else { return .tooLarge }
        // Twice the size wanted: the last halving is drawn at high quality, which ImageIO's own scaling is not. The
        // longer side stops at `longestSide` times that, so a long thin image is not decoded into a long bitmap.
        let limit = Int(CGFloat(pixels * 2) * longestSide)
        let wanted = Int((Double(pixels * 2) * Double(longer) / Double(shorter)).rounded(.up))
        guard let decoded = source.thumbnail(at: best, maxPixelSize: min(longer, wanted, limit)), decoded.width > 0, decoded.height > 0, max(decoded.width, decoded.height) <= limit
        else { return .unusable }
        let factor = min(
            1,
            CGFloat(pixels) / CGFloat(min(decoded.width, decoded.height)),
            CGFloat(pixels) * longestSide / CGFloat(max(decoded.width, decoded.height))
        )
        let width = max(1, Int((CGFloat(decoded.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(decoded.height) * factor).rounded()))
        // Drawn even at its own size, so every thumbnail is sRGB whatever profile the file carries.
        let drawn = bitmap(width: width, height: height) { $0.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        return drawn.map(Downsampled.image) ?? .unusable
    }

    /// How many times `pixels` a drawing's longer side may reach: a stranger shape is drawn smaller.
    static let longestSide: CGFloat = 4

    /// The most pixels an image may hold to be decoded at all, a 10,000 by 10,000 picture: ImageIO may decode more
    /// than the thumbnail it hands back, and a file can claim any size in a few bytes.
    static let maxSourcePixels = 100_000_000

    /// For what ImageIO does not downsample, SVG above all: drawn so its shorter side is `pixels`,
    /// unless that would make the longer side more than `longestSide` times as long.
    private static func drawn(_ image: NSImage, pixels: Int) -> CGImage? {
        let shorter = min(image.size.width, image.size.height)
        let longer = max(image.size.width, image.size.height)
        guard shorter > 0, longer.isFinite else { return nil }
        let factor = min(CGFloat(pixels) / shorter, CGFloat(pixels) * longestSide / longer)
        let width = max(1, Int((image.size.width * factor).rounded()))
        let height = max(1, Int((image.size.height * factor).rounded()))
        return draw(image, width: width, height: height, scale: factor)
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

/// Images on the web, for icons and for the pictures in Markdown. An extension names the address, so the
/// fetch is bounded: the web only, a few redirects that keep https, half a minute, and 8 MiB.
nonisolated enum RemoteImage {
    static let byteLimit = 8 << 20
    static let redirectLimit = 10
    static let timeout: TimeInterval = 30

    /// Only an absolute web address is fetched.
    static func accepts(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host?.isEmpty == false
    }

    /// Whether to follow the redirect that would be the `count`th, from `old` to `new`: never from https down to http.
    static func follows(redirectTo new: URL, from old: URL, count: Int) -> Bool {
        count <= redirectLimit && accepts(new) && !(old.scheme?.lowercased() == "https" && new.scheme?.lowercased() == "http")
    }

    /// The bytes at `url`, or nil for a failed request, an answer that is not a success, or one past the limit.
    static func data(at url: URL) async -> Data? {
        guard accepts(url) else { return nil }
        let request = URLRequest(url: url, timeoutInterval: timeout)
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request, delegate: RedirectGuard()), (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? false
        else { return nil }
        return await collect(bytes, expected: response.expectedContentLength)
    }

    /// Reads at most `limit` bytes: a length said up front past it is refused unread, and a stream that runs past it is dropped.
    static func collect<Bytes: AsyncSequence>(_ bytes: Bytes, expected: Int64, limit: Int = byteLimit) async -> Data? where Bytes.Element == UInt8 {
        guard expected <= Int64(limit) else { return nil }
        var data = Data()
        // A length the server states is not trusted with more than a megabyte up front.
        if expected > 0 {
            data.reserveCapacity(min(Int(expected), 1 << 20))
        }
        var chunk: [UInt8] = []
        chunk.reserveCapacity(chunkSize)
        do {
            for try await byte in bytes {
                chunk.append(byte)
                guard chunk.count == chunkSize else { continue }
                guard data.count + chunk.count <= limit else { return nil }
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        } catch {
            return nil
        }
        guard data.count + chunk.count <= limit else { return nil }
        data.append(contentsOf: chunk)
        return data
    }

    /// Bytes are gathered this many at a time before they join the data, rather than one by one.
    private static let chunkSize = 16 << 10

    /// Counts one fetch's redirects; a session-wide delegate could not tell the fetches apart.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        private let count = Mutex(0)

        func urlSession(
            _: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            let count = count.withLock { count in
                count += 1
                return count
            }
            guard let old = task.currentRequest?.url, let new = request.url, RemoteImage.follows(redirectTo: new, from: old, count: count) else {
                return completionHandler(nil)
            }
            completionHandler(request)
        }
    }

    /// Fetches and decodes off the main actor.
    @concurrent
    static func picture(at url: URL, maxPixels: Int) async -> CGImage? {
        guard let data = await data(at: url), !Task.isCancelled else { return nil }
        return image(from: data, maxPixels: maxPixels)
    }

    /// A picture decoded with its longer side at most `maxPixels`, so a large photo never exists at full size.
    static func image(from data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return source.thumbnail(at: CGImageSourceGetPrimaryImageIndex(source), maxPixelSize: maxPixels)
    }
}
