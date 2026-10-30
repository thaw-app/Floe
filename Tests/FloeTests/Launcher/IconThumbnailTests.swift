//
//  IconThumbnailTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers

struct IconThumbnailTests {
    /// Part of macOS itself, so the test does not depend on what is installed.
    private static let calculator = "/System/Applications/Calculator.app"

    private static nonisolated func solidImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func pngData(width: Int, height: Int) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, solidImage(width: width, height: height), nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A folder of generated images that goes away with the test.
    private static func withAssets(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-icons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private static func key(_ source: IconSource, points: CGFloat = 24, scale: CGFloat = 2) -> IconKey {
        IconKey(source: source, points: points, scale: scale)
    }

    @Test func theKeyTellsSizesScalesAndSourcesApart() {
        let row = Self.key(.workspace(path: Self.calculator))
        #expect(row.pixels == 48)
        #expect(Self.key(.workspace(path: Self.calculator), points: 16).cacheKey != row.cacheKey)
        #expect(Self.key(.workspace(path: Self.calculator), scale: 1).cacheKey != row.cacheKey)
        // 48 pt on a 1x display has the pixels of 24 pt at 2x, and is still its own artwork.
        #expect(Self.key(.workspace(path: Self.calculator), points: 48, scale: 1).cacheKey != row.cacheKey)
        #expect(Self.key(.file(path: Self.calculator)).cacheKey != row.cacheKey)
        #expect(Self.key(.workspace(path: "/System/Applications/Preview.app")).cacheKey != row.cacheKey)
        #expect(Self.key(.workspace(path: Self.calculator)).cacheKey == row.cacheKey)
    }

    @Test func aDataIconIsKeptByADigestOfItsURINotTheURIItself() {
        let large = "data:image/png;base64," + String(repeating: "A", count: 1_000_000)
        let key = Self.key(.data(uri: large))
        #expect(key.cacheKey.utf8.count < 200, "the cache keeps no copy of the image")
        #expect(key.cacheKey == Self.key(.data(uri: large)).cacheKey)
        #expect(key.cacheKey != Self.key(.data(uri: large + "B")).cacheKey)
    }

    @Test(arguments: [(24.0, 2.0, 48), (24.0, 1.0, 24), (16.0, 2.0, 32), (96.0, 2.0, 192)])
    func anAppIconComesOutAtThePixelsItIsDrawnIn(points: Double, scale: Double, pixels: Int) throws {
        let image = try #require(IconThumbnail.render(Self.key(.workspace(path: Self.calculator), points: points, scale: scale)))
        #expect(image.width == pixels)
        #expect(image.height == pixels)
    }

    @Test func aRemoteIconIsFetchedOnceAndKeptAtTheSizeItIsDrawn() async throws {
        let png = Self.pngData(width: 1024, height: 1024)
        let fetches = Mutex(0)
        let cache = IconThumbnailCache(budget: 1024 * 1024, render: { _ in nil }) { _ in
            fetches.withLock { $0 += 1 }
            return png
        }
        let key = try Self.key(.remote(url: #require(URL(string: "https://example.com/icon.png"))))
        let image = try #require(await cache.load(key))
        #expect(image.width == 48 && image.height == 48, "a 1024 px picture is kept as the 48 px the row draws")
        #expect(await cache.load(key) != nil)
        #expect(fetches.withLock(\.self) == 1, "the second row reads the kept thumbnail")
        #expect(try cache.imageRenderingNow(for: Self.key(.remote(url: #require(URL(string: "https://example.com/other.png"))))) == nil, "nothing is fetched in one pass")
    }

    @Test func aRemoteIconThatFailsToLoadIsNotKept() async throws {
        let cache = IconThumbnailCache(budget: 1024 * 1024, render: { _ in nil }) { _ in nil }
        let key = try Self.key(.remote(url: #require(URL(string: "https://example.com/missing.png"))))
        #expect(await cache.load(key) == nil)
        #expect(cache.image(for: key) == nil)
    }

    @Test func aMarkdownPictureIsDecodedNoLargerThanItsLongerSideAllows() throws {
        let image = try #require(RemoteImage.image(from: Self.pngData(width: 4000, height: 1000), maxPixels: 800))
        #expect(image.width == 800)
        #expect(image.height == 200)
        let small = try #require(RemoteImage.image(from: Self.pngData(width: 300, height: 100), maxPixels: 800))
        #expect(small.width == 300, "a small picture is not scaled up")
        #expect(RemoteImage.image(from: Data("not an image".utf8), maxPixels: 800) == nil)
    }

    @Test func onlyAnAbsoluteWebAddressIsFetched() async throws {
        #expect(try RemoteImage.accepts(#require(URL(string: "https://example.com/a.png"))))
        #expect(try RemoteImage.accepts(#require(URL(string: "HTTP://example.com/a.png"))))
        for refused in ["file:///etc/passwd", "ftp://example.com/a.png", "data:image/png;base64,AAAA", "https:///a.png", "/a.png"] {
            let url = try #require(URL(string: refused))
            #expect(!RemoteImage.accepts(url), "\(refused)")
            #expect(await RemoteImage.data(at: url) == nil, "\(refused) is never asked for")
        }
    }

    @Test func aRedirectIsFollowedTenTimesAtMostAndNeverFromHTTPSDownToHTTP() throws {
        let secure = try #require(URL(string: "https://example.com/a.png"))
        let plain = try #require(URL(string: "http://example.com/a.png"))
        #expect(RemoteImage.follows(redirectTo: secure, from: plain, count: 1))
        #expect(RemoteImage.follows(redirectTo: secure, from: secure, count: 10))
        #expect(!RemoteImage.follows(redirectTo: secure, from: secure, count: 11))
        #expect(!RemoteImage.follows(redirectTo: plain, from: secure, count: 1))
        #expect(try !RemoteImage.follows(redirectTo: #require(URL(string: "file:///etc/hosts")), from: plain, count: 1))
    }

    @Test func aDownloadStopsAtTheByteLimit() async {
        func stream(_ count: Int) -> AsyncStream<UInt8> {
            AsyncStream { continuation in
                for _ in 0 ..< count {
                    continuation.yield(0x41)
                }
                continuation.finish()
            }
        }
        #expect(await RemoteImage.collect(stream(16), expected: -1, limit: 16)?.count == 16, "exactly the limit is kept")
        #expect(await RemoteImage.collect(stream(17), expected: -1, limit: 16) == nil, "a length not said up front is counted")
        #expect(await RemoteImage.collect(stream(4), expected: 17, limit: 16) == nil, "a length said past the limit is not read")
        #expect(RemoteImage.byteLimit == 8 * 1024 * 1024)
        #expect(RemoteImage.timeout == 30)
    }

    @Test func imageIOKeepsNoDecodedImage() {
        let options = CGImageSource.thumbnailOptions(maxPixelSize: 64)
        #expect(options[kCGImageSourceShouldCache] as? Bool == false)
        #expect(options[kCGImageSourceShouldCacheImmediately] == nil, "it keeps each decoded image, 3 MB for a copied screenshot")
    }

    @Test func anImageFileIsDownsampledUntilItsShorterSideFillsTheSquare() throws {
        try Self.withAssets { folder in
            let wide = folder.appendingPathComponent("wide.png")
            try Self.pngData(width: 400, height: 200).write(to: wide)
            let image = try #require(IconThumbnail.render(Self.key(.file(path: wide.path))))
            #expect(image.width == 96)
            #expect(image.height == 48)
        }
    }

    @Test(arguments: [(1, 20000), (20000, 1), (100, 30000)])
    func aStrangelyShapedImageIsDrawnNoLongerThanTheLimit(width: Int, height: Int) throws {
        try Self.withAssets { folder in
            let strange = folder.appendingPathComponent("strange.png")
            try Self.pngData(width: width, height: height).write(to: strange)
            let image = try #require(IconThumbnail.render(Self.key(.file(path: strange.path))))
            #expect(CGFloat(max(image.width, image.height)) <= 48 * IconThumbnail.longestSide)
            #expect(min(image.width, image.height) >= 1)
        }
    }

    @Test func anImageTooLargeToDecodeIsNotDecoded() throws {
        // A PNG whose header says 100,000 by 100,000 pixels: ten billion, forty gigabytes decoded.
        let huge = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgABhqAAAYagCAYAAACoUgvIAAAADElEQVR4nGNgoAwAAABAAAG3NHzvAAAAAElFTkSuQmCC"))
        #expect(IconThumbnail.image(from: huge, pixels: 48) == nil)
    }

    @Test func aWholeImageTooLargeToDecodeIsRefusedAndNotHandedToNSImage() throws {
        // A complete, valid one-bit PNG just past the limit, which NSImage would read and decode whole.
        let side = 10001
        let rowBytes = (side + 7) / 8
        let provider = try #require(CGDataProvider(data: Data(count: rowBytes * side) as CFData))
        let picture = try #require(CGImage(
            width: side, height: side, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, picture, nil)
        #expect(CGImageDestinationFinalize(destination))

        let source = try #require(CGImageSourceCreateWithData(png, nil))
        guard case .tooLarge = IconThumbnail.downsampled(source, pixels: 48) else {
            Issue.record("a picture past the limit is told apart from one ImageIO can't use")
            return
        }
        #expect(IconThumbnail.image(from: png as Data, pixels: 48) == nil)
    }

    @Test func aSmallImageIsNotScaledUp() throws {
        try Self.withAssets { folder in
            let small = folder.appendingPathComponent("small.png")
            try Self.pngData(width: 20, height: 20).write(to: small)
            let image = try #require(IconThumbnail.render(Self.key(.file(path: small.path))))
            #expect(image.width == 20)
            #expect(image.height == 20)
        }
    }

    @Test func aVectorFileIsDrawnAtThePixelsWanted() throws {
        try Self.withAssets { folder in
            let vector = folder.appendingPathComponent("dot.svg")
            let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7"/></svg>"#
            try Data(svg.utf8).write(to: vector)
            let image = try #require(IconThumbnail.render(Self.key(.file(path: vector.path))))
            #expect(image.width == 48)
            #expect(image.height == 48)
        }
    }

    @Test func aDataURIIsDecodedAndDownsampled() throws {
        let uri = "data:image/png;base64," + Self.pngData(width: 256, height: 256).base64EncodedString()
        let image = try #require(IconThumbnail.render(Self.key(.data(uri: uri), points: 16)))
        #expect(image.width == 32)
        #expect(IconThumbnail.render(Self.key(.data(uri: "data:image/png;base64,not an image"))) == nil)
        #expect(IconThumbnail.data(fromURI: "data:text/plain,a%20b") == Data("a b".utf8))
    }

    @Test func aMissingFileHasNoThumbnail() {
        #expect(IconThumbnail.render(Self.key(.file(path: "/nonexistent/floe-icon.png"))) == nil)
    }

    @Test func theCostOfAnEntryIsTheBytesOfItsBitmap() throws {
        let image = try #require(IconThumbnail.render(Self.key(.workspace(path: Self.calculator))))
        #expect(IconThumbnailCache.cost(of: image) == image.bytesPerRow * image.height)
        #expect(IconThumbnailCache.cost(of: image) >= 48 * 48 * 4)
        // Row padding aside, a row icon is 9 KB: nothing of the 1024 px artwork is kept.
        #expect(IconThumbnailCache.cost(of: image) < 48 * 64 * 4)
    }

    @Test func aCachedThumbnailIsNotRenderedAgain() {
        let renders = Mutex(0)
        let cache = IconThumbnailCache(budget: 1024 * 1024) { _ in
            renders.withLock { $0 += 1 }
            return Self.solidImage(width: 48, height: 48)
        }
        let key = Self.key(.file(path: "/a.png"))
        #expect(cache.image(for: key) == nil)
        #expect(cache.imageRenderingNow(for: key) != nil)
        #expect(cache.imageRenderingNow(for: key) != nil)
        #expect(cache.image(for: key) != nil)
        #expect(cache.image(for: Self.key(.file(path: "/a.png"), scale: 1)) == nil)
        #expect(renders.withLock { $0 } == 1)
    }

    @Test func theBudgetEvicts() {
        let image = Self.solidImage(width: 48, height: 48)
        let cost = IconThumbnailCache.cost(of: image)
        let cache = IconThumbnailCache(budget: cost * 3) { _ in image }
        let keys = (0 ..< 12).map { Self.key(.file(path: "/icon-\($0).png")) }
        for key in keys {
            cache.store(image, for: key)
        }
        #expect(keys.filter { cache.image(for: $0) != nil } == Array(keys.suffix(3)), "the newest three are kept")
    }

    @Test func memoryPressureLetsGoOfEveryIconAndTheBudgetStartsOver() {
        let image = Self.solidImage(width: 48, height: 48)
        let cache = IconThumbnailCache(budget: IconThumbnailCache.cost(of: image) * 2) { _ in image }
        let first = Self.key(.file(path: "/first.png"))
        let second = Self.key(.file(path: "/second.png"))
        cache.store(image, for: first)
        cache.removeAll()
        #expect(cache.image(for: first) == nil)
        cache.store(image, for: first)
        cache.store(image, for: second)
        #expect(cache.image(for: first) != nil, "the budget counts only what was kept since")
        #expect(cache.image(for: second) != nil)
    }

    @Test func theIconUsedLongestAgoGoesFirst() {
        let image = Self.solidImage(width: 48, height: 48)
        let cache = IconThumbnailCache(budget: IconThumbnailCache.cost(of: image) * 2) { _ in image }
        let first = Self.key(.file(path: "/first.png"))
        let second = Self.key(.file(path: "/second.png"))
        cache.store(image, for: first)
        cache.store(image, for: second)
        // Drawn again just now, so it outlasts the one drawn after it.
        #expect(cache.image(for: first) != nil)
        cache.store(image, for: Self.key(.file(path: "/third.png")))
        #expect(cache.image(for: first) != nil)
        #expect(cache.image(for: second) == nil)
    }

    @Test func aLoadMakesTheThumbnailOffTheMainThread() async {
        let onMain = Mutex<Bool?>(nil)
        let cache = IconThumbnailCache(budget: 1024 * 1024) { _ in
            onMain.withLock { $0 = Thread.isMainThread }
            return Self.solidImage(width: 48, height: 48)
        }
        let key = Self.key(.file(path: "/a.png"))
        let image = await Task { @MainActor in await cache.load(key) }.value
        #expect(image != nil)
        #expect(onMain.withLock { $0 } == false)
        #expect(cache.image(for: key) != nil)
    }

    @Test func aLoadNobodyWaitsForIsNotMade() async {
        let renders = Mutex(0)
        let cache = IconThumbnailCache(budget: 1024 * 1024) { _ in
            renders.withLock { $0 += 1 }
            return Self.solidImage(width: 48, height: 48)
        }
        let key = Self.key(.file(path: "/gone.png"))
        // Cancelled before it starts, as a row's task is when the row scrolls away.
        let image = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cache.load(key)
        }.value
        #expect(image == nil)
        #expect(renders.withLock { $0 } == 0)
        #expect(cache.image(for: key) == nil)
    }

    @Test func anIconLoadedForAnotherPathIsNotShown() {
        let first = Self.key(.workspace(path: "/Applications/First.app"))
        let second = Self.key(.workspace(path: "/Applications/Second.app"))
        let loaded = LoadedIcon(key: first, image: Self.solidImage(width: 48, height: 48))
        #expect(loaded.image(for: first) != nil)
        #expect(loaded.image(for: second) == nil)
        #expect(loaded.image(for: Self.key(.workspace(path: "/Applications/First.app"), scale: 1)) == nil)
    }
}

extension IconThumbnailTests {
    @Test func aVectorFileOfAnyShapeGetsABoundedBitmap() throws {
        try Self.withAssets { folder in
            let vector = folder.appendingPathComponent("line.svg")
            let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="100000" viewBox="0 0 1 100000"><rect width="1" height="100000"/></svg>"#
            try Data(svg.utf8).write(to: vector)
            let image = try #require(IconThumbnail.render(Self.key(.file(path: vector.path))))
            #expect(image.height == 48 * Int(IconThumbnail.longestSide), "the longer side stops at its limit")
            #expect(image.width <= 48)
        }
    }
}
