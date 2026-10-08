//
//  ExchangeRatesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct ExchangeRatesTests {
    /// The bank's file as it is published, cut down to three currencies.
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
    <gesmes:subject>Reference rates</gesmes:subject>
    <Cube><Cube time='2026-10-07'>
    <Cube currency='USD' rate='1.25'/>
    <Cube currency='JPY' rate='160.0'/>
    <Cube currency='MXN' rate='20'/>
    </Cube></Cube>
    </gesmes:Envelope>
    """
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func scratchFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("floe-rates-\(UUID().uuidString)/ExchangeRates.json")
    }

    @Test func theBanksFileIsReadWithItsDayAndTheEuroAtOne() throws {
        let rates = try #require(ExchangeRates.parse(xml, fetched: day))
        #expect(rates.date == "2026-10-07")
        #expect(rates.rates == ["EUR": 1, "USD": 1.25, "JPY": 160, "MXN": 20])
        #expect(rates.fetched == day)
    }

    @Test(arguments: ["", "<html>Service unavailable</html>", "<Cube time='2026-10-07'></Cube>", "<Cube currency='USD' rate='1.25'/>", "<Cube time='2026-10-07'><Cube currency='USD' rate='0'/></Cube>"])
    func aFileWithNoDayOrNoRateIsNotRates(text: String) {
        #expect(ExchangeRates.parse(text, fetched: day) == nil)
    }

    @Test func ratesAgeAfterHalfADay() throws {
        let rates = try #require(ExchangeRates.parse(xml, fetched: day))
        #expect(!rates.isStale(at: day.addingTimeInterval(11 * 3600)))
        #expect(rates.isStale(at: day.addingTimeInterval(12 * 3600)))
        #expect(ExchangeRates.source?.host == "www.ecb.europa.eu")
    }

    @Test func ratesAreKeptInAFileAndTakenAwayAgain() throws {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(ExchangeRateStore.load(from: file) == nil)
        let rates = try #require(ExchangeRates.parse(xml, fetched: day))
        ExchangeRateStore.save(rates, to: file)
        #expect(ExchangeRateStore.load(from: file) == rates)
        ExchangeRateStore.remove(file)
        #expect(ExchangeRateStore.load(from: file) == nil)
    }

    @Test func theCalculatorConvertsMoneyOnlyWhileItHasRates() {
        let calculator = Calculator()
        #expect(calculator.evaluatePreview("10 EUR to USD")?.error == "To convert money, switch on exchange rates in Settings, Privacy.")

        calculator.setExchangeRates(["EUR": 1, "USD": 1.25, "JPY": 160])
        #expect(calculator.evaluatePreview("10 EUR to USD")?.result == "12.5 USD", "the answer remembered from before is not given again")
        #expect(calculator.evaluatePreview("320 JPY to USD")?.result == "2.5 USD")
        #expect(calculator.evaluatePreview("2 + 2")?.result == "4")

        calculator.setExchangeRates([:])
        #expect(calculator.evaluatePreview("10 EUR to USD")?.error == "To convert money, switch on exchange rates in Settings, Privacy.")
    }

    @Test func anAmountOfMoneySaysTheDayOfItsRatesAndNothingElseDoes() {
        let calculator = Calculator()
        #expect(calculator.ratesDate(for: "12.5 USD") == nil, "no rates, no day")
        calculator.setExchangeRates(["EUR": 1, "USD": 1.25], date: "2026-10-07")
        #expect(calculator.ratesDate(for: "12.5 USD") == "2026-10-07")
        #expect(calculator.ratesDate(for: "approx. 3.2 EUR") == "2026-10-07")
        #expect(calculator.ratesDate(for: "4") == nil)
        #expect(calculator.ratesDate(for: "12 km") == nil)
        #expect(calculator.ratesDate(for: "5 usd") == nil, "fend writes a code in capitals; a word in small letters is something else")
        calculator.setExchangeRates(["EUR": 1, "USD": 1.25])
        #expect(calculator.ratesDate(for: "12.5 USD") == nil, "rates given without a day")
        calculator.setExchangeRates([:])
        #expect(calculator.ratesDate(for: "12.5 USD") == nil)
    }

    @Test func nothingIsAskedForUntilTheSwitchIsOnAndOffTakesTheRatesAway() async throws {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let calculator = Calculator()
        let asked = Counter()
        let fresh = try #require(ExchangeRates.parse(xml, fetched: day))
        let updater = ExchangeRateUpdater(calculator: calculator, file: file, now: { day }, download: {
            asked.add()
            return fresh
        })

        #expect(updater.refreshIfStale() == nil)
        #expect(asked.times == 0, "off: the launcher opening asks for nothing")

        updater.set(on: true)
        await updater.refreshIfStale()?.value
        #expect(asked.times == 1)
        #expect(updater.rates == fresh)
        #expect(ExchangeRateStore.load(from: file) == fresh, "kept for the next launch")
        #expect(calculator.evaluatePreview("10 EUR to USD")?.result == "12.5 USD")

        await updater.refreshIfStale()?.value
        #expect(asked.times == 1, "fresh rates are not asked for again")

        updater.set(on: false)
        #expect(updater.rates == nil)
        #expect(ExchangeRateStore.load(from: file) == nil)
        #expect(calculator.evaluatePreview("10 EUR to USD")?.result.isEmpty == true)
    }

    @Test func ratesOnDiskAreUsedAtOnceAndAgedOnesAreAskedForAgain() async throws {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let old = try #require(ExchangeRates.parse(xml, fetched: day.addingTimeInterval(-24 * 3600)))
        ExchangeRateStore.save(old, to: file)
        let calculator = Calculator()
        let asked = Counter()
        let updater = ExchangeRateUpdater(calculator: calculator, file: file, now: { day }, download: {
            asked.add()
            return nil
        })

        updater.set(on: true)
        #expect(calculator.evaluatePreview("10 EUR to USD")?.result == "12.5 USD", "before any download answers")
        await updater.refreshIfStale()?.value
        #expect(asked.times == 1)
        #expect(updater.rates == old, "a download that fails leaves the rates held")
        #expect(calculator.evaluatePreview("10 EUR to USD")?.result == "12.5 USD")
    }

    @Test func theSwitchSaysWhatIsAskedAndTheDayOfTheRatesHeld() {
        #expect(PrivacyNetwork.exchangeRatesLine(held: nil).contains("European Central Bank"))
        #expect(!PrivacyNetwork.exchangeRatesLine(held: nil).contains("holds the rates"))
        #expect(PrivacyNetwork.exchangeRatesLine(held: "2026-10-07").hasSuffix("Floe holds the rates of 2026-10-07."))
    }

    @Test func theSwitchIsOffUntilTheUserTurnsItOnAndIsKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-rates-tests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.fetchesExchangeRates)
        settings.fetchesExchangeRates = true
        settings.save()
        #expect(AppSettings(defaults: defaults).fetchesExchangeRates)
    }
}

/// How many times the stand-in download was asked, which happens off the main actor.
private final nonisolated class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func add() {
        lock.withLock { value += 1 }
    }

    var times: Int {
        lock.withLock { value }
    }
}
