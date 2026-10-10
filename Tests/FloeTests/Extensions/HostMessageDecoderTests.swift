//
//  HostMessageDecoderTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct HostMessageDecoderTests {
    /// A full NDJSON line, the way the host writes it.
    private func line(_ json: [String: Any]) -> Data {
        (try! JSONSerialization.data(withJSONObject: json)) + Data("\n".utf8)
    }

    private func types(_ messages: [DecodedHostMessage]) -> [String] {
        messages.map { name(of: $0) }
    }

    private func fields(_ message: DecodedHostMessage) -> [String: Any] {
        guard case let .fields(value) = message else { return [:] }
        return value
    }

    private func tree(_ message: DecodedHostMessage) -> Node? {
        guard case let .render(value) = message else { return nil }
        return value
    }

    private func name(of message: DecodedHostMessage) -> String {
        switch message {
        case .render: "render"
        case .unresolvedRender: "unresolvedRender"
        case let .fields(fields): fields["type"] as? String ?? ""
        }
    }

    @Test func aMessageIsReassembledAtEverySplitPosition() async {
        let message = line(["type": "hud", "title": "Copied", "message": "done"])
        for split in message.indices {
            let decoder = HostMessageDecoder()
            let before = await decoder.append(message[..<split])
            let after = await decoder.append(message[split...])
            #expect(before.isEmpty, "nothing completes before its newline arrives")
            #expect(types(after) == ["hud"])
            #expect(fields(after[0])["title"] as? String == "Copied")
        }
    }

    @Test func aSplitInsideAMultibyteCharacterIsReassembled() async throws {
        let bytes = Array(line(["type": "hud", "title": "wör👍d"]))
        let start = try #require(bytes.firstIndex(of: 0xF0))
        let split = start + 2
        let decoder = HostMessageDecoder()
        #expect(await decoder.append(Data(bytes[..<split])).isEmpty)
        let messages = await decoder.append(Data(bytes[split...]))
        #expect(types(messages) == ["hud"])
        #expect(fields(messages[0])["title"] as? String == "wör👍d")
    }

    @Test func linesCompleteInOrderAcrossAndWithinChunks() async {
        let decoder = HostMessageDecoder()
        let batch = line(["type": "render", "tree": ["type": "Detail", "id": 7]]) + line(["type": "close"])
        let messages = await decoder.append(batch)
        #expect(types(messages) == ["render", "close"])
        #expect(tree(messages[0])?.id == 7)
        #expect(await decoder.append(line(["type": "hud", "title": "One"])).map { types([$0]) } == [["hud"]])
    }

    @Test func unreadableLinesAreSkipped() async {
        let decoder = HostMessageDecoder()
        let garbage = Data("not json\n\n[1, 2]\n\"text\"\n42\nnull\n".utf8)
        #expect(await decoder.append(garbage).isEmpty)
        #expect(await decoder.append(line(["type": "close"])).map { types([$0]) } == [["close"]])
    }

    @Test func aTrailingPartialLineWaitsForItsNewline() async {
        let message = line(["type": "hud", "title": "Copied"])
        let decoder = HostMessageDecoder()
        #expect(await decoder.append(message.dropLast()).isEmpty)
        #expect(await decoder.append(Data("\n".utf8)).map { types([$0]) } == [["hud"]])
    }

    @Test func manyPartialAppendsKeepThePartialLineIntact() async {
        let message = line(["type": "hud", "title": "Copied", "message": "done"])
        for chunk in [1, 3, 17, message.count - 1, message.count] {
            let decoder = HostMessageDecoder()
            var received: [DecodedHostMessage] = []
            var offset = 0
            while offset < message.count {
                let end = min(offset + chunk, message.count)
                received += await decoder.append(message[offset ..< end])
                offset = end
            }
            #expect(received.map { types([$0]) } == [["hud"]], "chunk size \(chunk)")
            #expect(fields(received[0])["title"] as? String == "Copied", "chunk size \(chunk)")
        }
    }

    @Test func aRenderWithAnUnreadableTreeDecodesAsAnEmptyRoot() async {
        let decoder = HostMessageDecoder()
        #expect(await decoder.append(line(["type": "render", "tree": "nope"])).map { tree($0) == nil } == [true])
        #expect(await decoder.append(line(["type": "render"])).map { tree($0) == nil } == [true])
        let good = await decoder.append(line(["type": "render", "tree": ["type": "Detail", "id": 7]]))
        #expect(tree(good[0])?.id == 7)
        #expect(tree(good[0])?.type == "Detail")
    }

    @Test func decodersDoNotShareState() async {
        let first = HostMessageDecoder()
        let second = HostMessageDecoder()
        #expect(await first.append(Data("partial ".utf8)).isEmpty)
        #expect(await second.append(line(["type": "close"])).map { types([$0]) } == [["close"]])
        #expect(await first.append(Data("half\n".utf8)).isEmpty, "a malformed line is skipped, not kept forever")
        #expect(await first.append(line(["type": "hud", "title": "One"])).map { types([$0]) } == [["hud"]])
    }

    /// Suspends its waiter until it is opened, so ordering tests never sleep.
    private actor Gate {
        private var waiter: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen {
                return
            }
            await withCheckedContinuation { waiter = $0 }
        }

        func open() {
            isOpen = true
            waiter?.resume()
            waiter = nil
        }
    }

    @Test func aSuspendedApplicationHoldsBackTheNextChunk() async {
        let decoder = HostMessageDecoder()
        let firstApplied = Gate()
        let release = Gate()
        var applied: [String] = []

        let delivery = Task {
            await decoder.deliver(line(["type": "hud", "title": "One"])) { @MainActor message in
                applied.append(name(of: message))
                await firstApplied.open()
                await release.wait()
            }
            await decoder.deliver(line(["type": "close"])) { @MainActor message in
                applied.append(name(of: message))
            }
        }

        await firstApplied.wait()
        #expect(applied == ["hud"], "the second chunk is not consumed while the first application is suspended")
        await release.open()
        _ = await delivery.result
        #expect(applied == ["hud", "close"])
    }

    // MARK: Timings

    /// Opt-in samples (FLOE_PERF_REPORT=1) for the same synthetic trees the old receive path measured:
    /// decoding alone, and decoding plus main-actor application. Application runs on the test's main
    /// actor, so the combined samples exclude the MainActor.run hop the process relay pays.
    @Test(.disabled(if: ProcessInfo.processInfo.environment["FLOE_PERF_REPORT"] == nil))
    @MainActor
    func reportDecoderTimings() async throws {
        let session = ExtensionSession(command: Fixture.command("planets"))
        for count in [1000, 10000] {
            let message = try JSONSerialization.data(withJSONObject: ["type": "render", "tree": Self.syntheticTree(count: count)]) + Data("\n".utf8)
            let chunks = stride(from: 0, to: message.count, by: 1024).map { start in
                message[start ..< min(start + 1024, message.count)]
            }
            var decodeOnly: [Double] = []
            var decodeOnlyKib: [Double] = []
            var decodeAndApply: [Double] = []
            var decodeAndApplyKib: [Double] = []
            for _ in 0 ..< 5 {
                let decoder = HostMessageDecoder()
                await decodeAndApply.append(Self.milliseconds {
                    for decoded in await decoder.append(message) {
                        session.apply(decoded)
                    }
                })
                #expect(session.rows.map(\.id) == Array(100 ..< 100 + count), "the whole tree is applied")
                await decodeAndApplyKib.append(Self.milliseconds {
                    for chunk in chunks {
                        for decoded in await decoder.append(chunk) {
                            session.apply(decoded)
                        }
                    }
                })
                #expect(session.rows.map(\.id) == Array(100 ..< 100 + count), "chunks reassemble into the same tree")

                let lone = HostMessageDecoder()
                await decodeOnly.append(Self.milliseconds { _ = await lone.append(message) })
                await decodeOnlyKib.append(Self.milliseconds {
                    for chunk in chunks {
                        _ = await lone.append(chunk)
                    }
                })
            }
            Self.report("decoder", items: count, oneChunk: decodeOnly, inKibChunks: decodeOnlyKib)
            Self.report("decoder+apply", items: count, oneChunk: decodeAndApply, inKibChunks: decodeAndApplyKib)
        }
    }

    private static func syntheticTree(count: Int) -> [String: Any] {
        Fixture.node("root", id: 0, children: [
            Fixture.node("_screen", id: 2, children: [
                Fixture.node("List", id: 3, children: (0 ..< count).map { index in
                    Fixture.item("Item \(index)", id: 100 + index, actions: [Fixture.action("Show", id: 100_000 + index)])
                }),
            ]),
        ])
    }

    private static func milliseconds(_ body: () async -> Void) async -> Double {
        let start = DispatchTime.now()
        await body()
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private static func report(_ label: String, items: Int, oneChunk: [Double], inKibChunks: [Double]) {
        func format(_ samples: [Double]) -> String {
            samples.map { String(format: "%.2f", $0) }.joined(separator: ", ")
        }
        print("[perf] \(label) items=\(items) oneChunk(ms)=\(format(oneChunk)) kibChunks(ms)=\(format(inKibChunks))")
    }
}
