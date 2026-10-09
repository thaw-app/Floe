import Foundation
import Testing
@testable import FendCore

@Suite("FileIndex Tests")
struct FileIndexTests {
    /// A folder of its own in the temporary folder, with the given files in it.
    private func scratch(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floe-file-index-\(UUID().uuidString)")
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("A build lists what the rules keep, and a search finds it with its matched letters")
    func testBuildAndSearch() throws {
        let root = try scratch(["Documents/invoice.pdf", "node_modules/pkg/invoice.js", "Tool.app/Contents/invoice.txt", ".hidden/invoice.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = try FileIndex()
        #expect(index.count == 0)
        let built = index.build(root: root.path, excludedNames: ["node_modules"], packageSuffixes: [".app"])
        #expect(built == 3)
        #expect(index.count == 3)
        #expect(index.byteSize > 0)

        let hits = index.search("inv", limit: 10)
        #expect(hits.map(\.path) == [root.path + "/Documents/invoice.pdf"])
        #expect(hits.first?.isFolder == false)
        #expect(hits.first?.matched == [0, 1, 2])
        #expect((hits.first?.score ?? 0) > 0)

        let folders = index.search("Documents", limit: 10)
        #expect(folders.first?.isFolder == true)
        #expect(index.search("inv", limit: 0).isEmpty)
        #expect(index.search("", limit: 10).isEmpty)
    }

    @Test("A rescan takes in what changed in one folder")
    func testRescan() throws {
        let root = try scratch(["notes/first.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = try FileIndex()
        index.build(root: root.path)
        try Data().write(to: root.appendingPathComponent("notes/second.txt"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/first.txt"))
        #expect(index.search("second", limit: 10).isEmpty)
        index.rescan(root.path + "/notes")
        #expect(index.search("second", limit: 10).count == 1)
        #expect(index.search("first", limit: 10).isEmpty)
        #expect(index.count == 2)
    }

    @Test("A missing root builds an empty index")
    func testMissingRoot() throws {
        let index = try FileIndex()
        #expect(index.build(root: "/floe-tests-no-such-folder") == 0)
        #expect(index.search("a", limit: 10).isEmpty)
    }

    @Test("A block that ends early gives the hits read before the end")
    func testTruncatedBlock() {
        var block: [UInt8] = [2, 0, 0, 0]
        block += [7, 0, 0, 0, 1, 2, 0, 0, 0] + Array("/a".utf8) + [1, 0, 0, 0, 0, 0, 0, 0]
        block += [9, 0, 0, 0, 0, 200, 0, 0, 0]
        let hits = block.withUnsafeBytes { FileIndex.hits(in: $0) }
        #expect(hits == [FileIndex.Hit(path: "/a", isFolder: true, score: 7, matched: [0])])
        #expect([UInt8]().withUnsafeBytes { FileIndex.hits(in: $0) }.isEmpty)
    }
}
