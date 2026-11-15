//
//  Scrypt.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//

import CryptoKit
import Foundation

/// The scrypt key derivation of RFC 7914, which CryptoKit does not have. Raycast derives the key of its backups with it.
nonisolated enum Scrypt {
    enum Failure: Error {
        case invalidParameters
    }

    /// The key for password and salt. cost is N, a power of two above 1; blockSize is r; parallelism is p.
    static func derive(password: Data, salt: Data, cost: Int, blockSize: Int, parallelism: Int, length: Int) throws -> Data {
        guard cost > 1, cost & (cost - 1) == 0, blockSize > 0, parallelism > 0, length > 0 else {
            throw Failure.invalidParameters
        }
        let chunk = 128 * blockSize
        var blocks = pbkdf2(password: password, salt: salt, length: parallelism * chunk)
        for index in 0 ..< parallelism {
            let range = index * chunk ..< (index + 1) * chunk
            blocks.replaceSubrange(range, with: mix(Data(blocks[range]), cost: cost, blockSize: blockSize))
        }
        return pbkdf2(password: password, salt: blocks, length: length)
    }

    /// PBKDF2 with HMAC-SHA256 and one iteration, which is all scrypt asks of it.
    private static func pbkdf2(password: Data, salt: Data, length: Int) -> Data {
        let key = SymmetricKey(data: password)
        var output = Data(capacity: length)
        var counter: UInt32 = 1
        while output.count < length {
            var message = salt
            withUnsafeBytes(of: counter.bigEndian) { message.append(contentsOf: $0) }
            output.append(contentsOf: HMAC<SHA256>.authenticationCode(for: message, using: key))
            counter += 1
        }
        return output.prefix(length)
    }

    /// ROMix: fills cost copies of the block, then reads them back in an order that depends on the block.
    private static func mix(_ block: Data, cost: Int, blockSize: Int) -> Data {
        let words = 32 * blockSize
        let x = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: words)
        let scratch = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: words)
        let table = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: cost * words)
        defer {
            x.deallocate()
            scratch.deallocate()
            table.deallocate()
        }
        block.withUnsafeBytes { raw in
            for index in 0 ..< words {
                x[index] = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self))
            }
        }
        for row in 0 ..< cost {
            UnsafeMutableBufferPointer(rebasing: table[row * words ..< (row + 1) * words]).update(fromContentsOf: x)
            blockMix(x, scratch: scratch, blockSize: blockSize)
        }
        for _ in 0 ..< cost {
            let row = Int(x[words - 16] & UInt32(cost - 1)) * words
            for index in 0 ..< words {
                x[index] ^= table[row + index]
            }
            blockMix(x, scratch: scratch, blockSize: blockSize)
        }
        var output = Data(capacity: words * 4)
        for word in x {
            withUnsafeBytes(of: word.littleEndian) { output.append(contentsOf: $0) }
        }
        return output
    }

    /// BlockMix with Salsa20/8, writing the even 64-byte pieces before the odd ones, then back into block.
    private static func blockMix(_ block: UnsafeMutableBufferPointer<UInt32>, scratch: UnsafeMutableBufferPointer<UInt32>, blockSize: Int) {
        var state = Salsa(block, at: (2 * blockSize - 1) * 16)
        for piece in 0 ..< 2 * blockSize {
            state.mix(with: block, at: piece * 16)
            state.store(in: scratch, at: (piece / 2 + (piece % 2) * blockSize) * 16)
        }
        _ = block.update(fromContentsOf: scratch)
    }
}

/// The 16 words Salsa20/8 works on, kept out of the heap.
private nonisolated struct Salsa {
    private var words: SIMD16<UInt32>

    init(_ source: UnsafeMutableBufferPointer<UInt32>, at offset: Int) {
        words = SIMD16(source[offset ..< offset + 16])
    }

    func store(in destination: UnsafeMutableBufferPointer<UInt32>, at offset: Int) {
        for index in 0 ..< 16 {
            destination[offset + index] = words[index]
        }
    }

    /// XORs in 16 words, then runs the Salsa20 core with 8 rounds and adds the input back.
    mutating func mix(with source: UnsafeMutableBufferPointer<UInt32>, at offset: Int) {
        words ^= SIMD16(source[offset ..< offset + 16])
        var x = words
        for _ in 0 ..< 4 {
            Self.quarter(&x, 0, 4, 8, 12)
            Self.quarter(&x, 5, 9, 13, 1)
            Self.quarter(&x, 10, 14, 2, 6)
            Self.quarter(&x, 15, 3, 7, 11)
            Self.quarter(&x, 0, 1, 2, 3)
            Self.quarter(&x, 5, 6, 7, 4)
            Self.quarter(&x, 10, 11, 8, 9)
            Self.quarter(&x, 15, 12, 13, 14)
        }
        words &+= x
    }

    // swiftlint:disable:next identifier_name
    private static func quarter(_ x: inout SIMD16<UInt32>, _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        x[b] ^= (x[a] &+ x[d]).rotated(7)
        x[c] ^= (x[b] &+ x[a]).rotated(9)
        x[d] ^= (x[c] &+ x[b]).rotated(13)
        x[a] ^= (x[d] &+ x[c]).rotated(18)
    }
}

private extension UInt32 {
    nonisolated func rotated(_ count: UInt32) -> UInt32 {
        (self << count) | (self >> (32 - count))
    }
}
