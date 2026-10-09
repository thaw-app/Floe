import CFendCore
import Foundation

/// The names of the files under one folder, held in memory and matched fuzzily.
/// Every call may come from any thread: the library locks around its own state.
public final class FileIndex: @unchecked Sendable {
    public struct Hit: Equatable, Sendable {
        public let path: String
        public let isFolder: Bool
        public let score: Int
        /// The offsets, in characters, of the letters of the file name that the query matched.
        public let matched: [Int]

        public init(path: String, isFolder: Bool, score: Int, matched: [Int]) {
            self.path = path
            self.isFolder = isFolder
            self.score = score
            self.matched = matched
        }
    }

    private let pointer: OpaquePointer

    public init() throws {
        guard let pointer = floe_index_new() else {
            throw FendError.contextAllocationFailed
        }
        self.pointer = pointer
    }

    deinit {
        floe_index_free(pointer)
    }

    /// Walks `root`, replaces what the index holds and returns the number of entries. Dot names and
    /// `excludedNames` are left out; a folder ending in one of `packageSuffixes` is listed and not entered.
    @discardableResult
    public func build(root: String, excludedNames: [String] = [], packageSuffixes: [String] = []) -> Int {
        Self.withCStrings(excludedNames) { names in
            Self.withCStrings(packageSuffixes) { suffixes in
                max(0, Int(floe_index_build(pointer, root, names, names.count, suffixes, suffixes.count)))
            }
        }
    }

    /// Brings one folder in line with the disk: what is directly in it, or with `recursive` everything under it.
    public func rescan(_ path: String, recursive: Bool = false) {
        floe_index_rescan(pointer, path, recursive)
    }

    /// The best matches for a query, best first. The file name is matched; a query with a slash matches the path.
    public func search(_ query: String, limit: Int) -> [Hit] {
        var length = 0
        guard limit > 0, let block = floe_index_search(pointer, query, limit, &length) else { return [] }
        defer { floe_index_block_free(block, length) }
        return Self.hits(in: UnsafeRawBufferPointer(start: block, count: length))
    }

    public var count: Int {
        floe_index_count(pointer)
    }

    /// Roughly how much memory the index holds, in bytes.
    public var byteSize: Int {
        floe_index_byte_size(pointer)
    }

    /// Reads the block `floe_index_search` describes in the header. A block that ends early gives the hits read so far.
    static func hits(in block: UnsafeRawBufferPointer) -> [Hit] {
        var offset = 0
        func number() -> Int? {
            guard offset + 4 <= block.count else { return nil }
            defer { offset += 4 }
            return Int(UInt32(littleEndian: block.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        }
        guard let count = number() else { return [] }
        var hits: [Hit] = []
        for _ in 0..<count {
            guard let score = number(), offset < block.count else { break }
            let isFolder = block[offset] == 1
            offset += 1
            guard let pathLength = number(), offset + pathLength <= block.count else { break }
            let path = String(decoding: block[offset..<offset + pathLength], as: UTF8.self)
            offset += pathLength
            guard let matchedCount = number(), offset + matchedCount * 4 <= block.count else { break }
            let matched = (0..<matchedCount).compactMap { _ in number() }
            hits.append(Hit(path: path, isFolder: isFolder, score: score, matched: matched))
        }
        return hits
    }

    private static func withCStrings<Result>(_ strings: [String], _ body: ([UnsafePointer<CChar>?]) -> Result) -> Result {
        let copies = strings.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        return body(copies.map { UnsafePointer($0) })
    }
}
