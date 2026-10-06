//
//  FendCorpusReplayTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@Suite("fend corpus replay")
struct FendCorpusReplayTests {
    private static let cases = FendCorpusReplay.parse(FendIntegrationCorpus.text)

    // MARK: Parser characterization

    @Test func theParserRecoversEveryCallInTheFixture() {
        let written = FendIntegrationCorpus.text.components(separatedBy: "test_eval").count - 1
        #expect(Self.cases.count == written, "a call in the fixture is in a shape the parser does not read")
        #expect(Self.cases.count > 1000)
        #expect(Self.cases.first == .init(input: "2", expected: "2"))
    }

    @Test func aCallOverSeveralLinesIsOneCase() {
        let long = "315427679023453451289740 * 927346502937456234523452"
        #expect(Self.cases.first { $0.input == long }?.expected == "292510755072077978255166497050046859223676982480")
    }

    @Test(arguments: [
        (#"a \"quoted\" word"#, "a \"quoted\" word"),
        (#"two\nlines\tand a tab"#, "two\nlines\tand a tab"),
        (#"back\\slash"#, "back\\slash"),
        (#"\x41\u{e9}\u{1F600}"#, "Aé😀"),
        ("joined \\\n\t\t  here", "joined here"),
    ])
    func aRustLiteralIsReadAsTheTextItStandsFor(literal: String, text: String) {
        #expect(FendCorpusReplay.unescaped(literal) == text)
    }

    // MARK: What is left out on purpose

    @Test(arguments: ["2", " 10 ", "1,000.5", "39456720983475234523452345", ""])
    func aNumberAloneIsNotACalculation(input: String) {
        #expect(FendCorpusReplay.isNotACalculation(input))
    }

    @Test(arguments: ["2+2", "pi", "0x10", "5 km", "-3"])
    func anythingElseIsOne(input: String) {
        #expect(!FendCorpusReplay.isNotACalculation(input))
    }

    @Test func anInexactAnswerIsWordedWithASign() {
        #expect(FendCorpusReplay.presented("approx. 0.3333333333") == "≈ 0.3333333333")
        #expect(FendCorpusReplay.presented("14") == "14")
    }

    @Test(arguments: [
        ("≈ 0.2777777778 m/s", "approx. 0.2777777778 m / s", "0m/s + 1 km/hr"),
        ("F₁₆", "0xf", "0x10 - 1"),
        ("10000₂", "10000", "16 to base 2"),
        ("≈ 10.1011100000₂", "approx. 10.1011100000", "e in binary"),
        ("16", "0x10", "0x10"),
        ("255", "0xff", "0x0000_00ff"),
    ])
    func aChoiceOfPresentationIsStillTheSameAnswer(shown: String, expected: String, input: String) {
        #expect(FendCorpusReplay.isSameAnswer(shown: shown, expected: expected, input: input))
    }

    @Test(arguments: [
        ("≈ 1.5707963268 - 1", "approx. 1.5707963268 - 1.762747174i", "asin 3"),
        ("≈ 1.219326311e+17", "121932631112635269", "123456789 * 987654321"),
        ("F₁₆", "0xe", "0x10 - 2"),
        ("10001₂", "10000", "16 to base 2"),
        ("17", "0x10", "0x10"),
        ("16", "0x10", "0x10 + 0"),
        ("1 s^2", "1 second^2", "1 second second"),
    ])
    func aChangedDigitOrUnitIsNot(shown: String, expected: String, input: String) {
        #expect(!FendCorpusReplay.isSameAnswer(shown: shown, expected: expected, input: input))
    }

    // MARK: Replay

    /// The whole of it: every input of fend's tests typed into Floe, against the ledger.
    @Test func floeShowsWhatFendsOwnTestsExpectExceptWhatTheLedgerHolds() throws {
        let now = FendCorpusReplay.currentLedger(of: Self.cases)
        // The run that rewrites the ledger was compiled with the old one, so it compares nothing.
        if ProcessInfo.processInfo.environment["FLOE_WRITE_FEND_LEDGER"] == "1" {
            try FendCorpusReplay.ledgerSource(now).write(to: FendCorpusReplay.ledgerFile(), atomically: true, encoding: .utf8)
            return
        }
        let held = FendCorpusReplay.lines(ofLedger: FendCorpusLedger.text)
        let new = Set(now).subtracting(held).sorted()
        let gone = Set(held).subtracting(now).sorted()
        #expect(new.isEmpty, "\(new.count) not in the ledger. Floe no longer shows what fend expects, first: \(new.prefix(5))")
        #expect(gone.isEmpty, "\(gone.count) in the ledger are no longer true. Rewrite it with FLOE_WRITE_FEND_LEDGER=1, first: \(gone.prefix(5))")
    }

    /// The copied text is held to fend's answers above. This holds what is drawn to what it was when last recorded.
    @Test func whatIsDrawnForTheCorpusIsWhatWasRecorded() throws {
        let now = FendCorpusReplay.drawnRecord(of: Self.cases)
        if ProcessInfo.processInfo.environment["FLOE_WRITE_FEND_LEDGER"] == "1" {
            try FendCorpusReplay.drawnSource(now).write(to: FendCorpusReplay.drawnFile(), atomically: true, encoding: .utf8)
            return
        }
        let recorded = FendCorpusReplay.lines(ofLedger: FendCorpusDrawn.text)
        let changed = Set(now).symmetricDifference(recorded).sorted()
        #expect(changed.isEmpty, "\(changed.count) lines differ from the record. If the change is meant, rewrite it with FLOE_WRITE_FEND_LEDGER=1, first: \(changed.prefix(6))")
    }

    @Test func mostOfTheCorpusIsShownAsFendAnswersIt() {
        let held = FendCorpusReplay.lines(ofLedger: FendCorpusLedger.text).count
        #expect(Self.cases.count - held > Self.cases.count / 2, "the ledger holds more of the corpus than Floe gets right")
    }
}
