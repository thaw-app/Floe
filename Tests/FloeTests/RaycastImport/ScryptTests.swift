//
//  ScryptTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The test vectors in RFC 7914, section 12. OpenSSL's `kdf SCRYPT` gives the same keys.
struct ScryptTests {
    @Test func anEmptyPasswordAndSaltGiveTheRFCKey() throws {
        let key = try Scrypt.derive(password: Data(), salt: Data(), cost: 16, blockSize: 1, parallelism: 1, length: 64)
        #expect(key.hexadecimal == """
        77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442\
        fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906
        """)
    }

    @Test func passwordAndNaClGiveTheRFCKey() throws {
        let key = try Scrypt.derive(password: Data("password".utf8), salt: Data("NaCl".utf8), cost: 1024, blockSize: 8, parallelism: 16, length: 64)
        #expect(key.hexadecimal == """
        fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162\
        2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640
        """)
    }

    /// The cost Raycast uses for its backups.
    @Test func pleaseLetMeInGivesTheRFCKey() throws {
        let key = try Scrypt.derive(password: Data("pleaseletmein".utf8), salt: Data("SodiumChloride".utf8), cost: 16384, blockSize: 8, parallelism: 1, length: 64)
        #expect(key.hexadecimal == """
        7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2\
        d5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887
        """)
    }

    @Test func aCostThatIsNotAPowerOfTwoIsRefused() {
        #expect(throws: Scrypt.Failure.self) {
            try Scrypt.derive(password: Data(), salt: Data(), cost: 1000, blockSize: 1, parallelism: 1, length: 32)
        }
    }
}
