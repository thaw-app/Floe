//
//  QuicklinkURLTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct QuicklinkURLTests {
    private func link(_ template: String, _ query: String) -> String? {
        url(for: Quicklink(name: "Link", keyword: "l", url: template), query: query)?.absoluteString
    }

    @Test func textInTheQueryIsOneValueAndCannotAddAField() {
        #expect(link("mailto:me@example.com?subject={query}", "hi&cc=x@y.z&bcc=w@y.z") == "mailto:me@example.com?subject=hi%26cc%3Dx%40y.z%26bcc%3Dw%40y.z")
        #expect(link("https://www.google.com/search?q={query}", "a+b c#d?e=f") == "https://www.google.com/search?q=a%2Bb%20c%23d%3Fe%3Df")
        #expect(link("https://example.com/#{query}", "a&b/c") == "https://example.com/#a%26b%2Fc")
    }

    @Test func textInThePathKeepsItsSlashesAndNothingElseThatEndsThePath() {
        #expect(link("https://github.com/{query}", "apple/swift") == "https://github.com/apple/swift")
        #expect(link("https://time.is/{query}", "New York?x=1#y") == "https://time.is/New%20York%3Fx%3D1%23y")
        #expect(link("https://{query}.example.com/", "evil.com@") == "https://evil.com%40.example.com/", "the text cannot name another host")
        #expect(link("https://{query}.example.com/", "evil.com/") == "https://evil.com%2F.example.com/", "nor end the host with a slash of its own")
        #expect(link("https://{query}", "evil.com/x") == "https://evil.com%2Fx", "a host the whole text makes up keeps no slash either")
        #expect(link("https://example.com/{query}?q={query}", "a/b") == "https://example.com/a/b?q=a%2Fb", "each place is encoded for where it is")
    }

    @Test func aLinkWithoutThePlaceholderOpensAsItIs() {
        #expect(link("https://example.com/?a=1&b=2", "ignored") == "https://example.com/?a=1&b=2")
    }
}
