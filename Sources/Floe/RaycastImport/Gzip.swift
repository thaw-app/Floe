//
//  Gzip.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import Foundation
import zlib

nonisolated enum Gzip {
    /// The bytes inside a gzip stream, or nil when it is not one or would grow past `limit`.
    static func decompress(_ data: Data, limit: Int) -> Data? {
        guard !data.isEmpty else { return nil }
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var input = [UInt8](data)
        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let finished = input.withUnsafeMutableBufferPointer { inBuffer -> Bool in
            stream.next_in = inBuffer.baseAddress
            stream.avail_in = UInt32(inBuffer.count)
            while true {
                let status = chunk.withUnsafeMutableBufferPointer { outBuffer in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = UInt32(outBuffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                output.append(contentsOf: chunk.prefix(chunk.count - Int(stream.avail_out)))
                guard output.count <= limit else { return false }
                if status == Z_STREAM_END { return true }
                guard status == Z_OK else { return false }
            }
        }
        return finished ? output : nil
    }
}
