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

    @Test(arguments: [(24.0, 2.0, 48), (24.0, 1.0, 24), (16.0, 2.0, 32), (96.0, 2.0, 192)])
    func anAppIconComesOutAtThePixelsItIsDrawnIn(points: Double, scale: Double, pixels: Int) throws {
        let image = try #require(IconThumbnail.render(Self.key(.workspace(path: Self.calculator), points: points, scale: scale)))
        #expect(image.width == pixels)
        #expect(image.height == pixels)
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
