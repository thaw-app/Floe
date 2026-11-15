//
//  RaycastBackup+Testing.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CryptoKit
@testable import Floe
import Foundation
import zlib

/// Builds a .rayconfig the way Raycast 2 writes one, so no real backup is ever kept as a fixture.
enum RaycastBackup {
    static let iv = Data((0 ..< 16).map { UInt8($0) })
    static let salt = Data((16 ..< 32).map { UInt8($0) })

    /// A scrypt cost low enough for a debug build. RaycastExport.read is given the same one.
    static let cost = 16

    static func make(payload: String, passphrase: String, schemaVersion: Int = 3, cost: Int = cost) throws -> Data {
        let header = #"{"schemaVersion":\#(schemaVersion),"encryption":{"iv":"\#(iv.hexadecimal)","salt":"\#(salt.hexadecimal)"}}"#
        let compressedHeader = gzip(Data(header.utf8))
        let key = try Scrypt.derive(password: Data(passphrase.utf8), salt: salt, cost: cost, blockSize: 8, parallelism: 1, length: 32)
        let box = try AES.GCM.seal(gzip(Data(payload.utf8)), using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: iv))
        var file = Data("RAYCFG3\n".utf8)
        withUnsafeBytes(of: UInt32(compressedHeader.count).littleEndian) { file.append(contentsOf: $0) }
        file.append(compressedHeader)
        file.append(box.ciphertext)
        file.append(box.tag)
        return file
    }

    static func gzip(_ data: Data) -> Data {
        var stream = z_stream()
        deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, UInt(input.count))) + 32)
        let written = input.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = UInt32(inBuffer.count)
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = UInt32(outBuffer.count)
                deflate(&stream, Z_FINISH)
                return outBuffer.count - Int(stream.avail_out)
            }
        }
        return Data(output.prefix(written))
    }
}
