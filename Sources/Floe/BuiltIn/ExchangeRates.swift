//
//  ExchangeRates.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The European Central Bank's reference rates for one day: how much of each currency one euro buys.
nonisolated struct ExchangeRates: Codable, Equatable, Sendable {
    /// The day the bank set them, as it writes it: 2026-10-07.
    var date: String
    /// By currency code, the euro among them at 1.
    var rates: [String: Double]
    /// When Floe downloaded them.
    var fetched: Date

    /// The file the bank publishes once each working day, at about 16:00 Central European Time. It is the same
    /// for everyone who asks: the request says nothing of the user or of what was typed.
    static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    /// How long a download is good for before another is made.
    static let lifetime: TimeInterval = 12 * 60 * 60

    /// Reads the bank's file: `<Cube time='2026-10-07'>` over one `<Cube currency='USD' rate='1.1177'/>` for each currency.
    /// Nil for a file with no date or no rate in it.
    static func parse(_ xml: String, fetched: Date) -> ExchangeRates? {
        guard let date = xml.firstMatch(of: /time=['"](\d{4}-\d{2}-\d{2})['"]/)?.1 else { return nil }
        var rates: [String: Double] = [:]
        for found in xml.matches(of: /currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/) {
            if let rate = Double(found.2), rate > 0 {
                rates[String(found.1)] = rate
            }
        }
        guard !rates.isEmpty else { return nil }
        rates["EUR"] = 1
        return ExchangeRates(date: String(date), rates: rates, fetched: fetched)
    }

    func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(fetched) >= Self.lifetime
    }
}

/// The last rates downloaded, kept in a file so money converts without the network and across launches.
nonisolated enum ExchangeRateStore {
    static var file: URL {
        Paths.support.appendingPathComponent("ExchangeRates.json")
    }

    static func load(from file: URL = file) -> ExchangeRates? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(ExchangeRates.self, from: $0) }
    }

    static func save(_ rates: ExchangeRates, to file: URL = file) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(rates).write(to: file, options: .atomic)
    }

    static func remove(_ file: URL = file) {
        try? FileManager.default.removeItem(at: file)
    }

    /// Downloads the bank's file. Nil when the network or the file fails: the rates held are kept.
    @concurrent
    static func download(now: Date = Date()) async -> ExchangeRates? {
        guard let source = ExchangeRates.source else { return nil }
        var request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(bytes: data, encoding: .utf8) else { return nil }
        return ExchangeRates.parse(xml, fetched: now)
    }
}

/// Keeps the calculator's exchange rates as the switch in Settings says: the ones on disk at once, and a
/// download when there are none or they have aged. With the switch off nothing is asked for and nothing is kept.
@MainActor
final class ExchangeRateUpdater {
    static let shared = ExchangeRateUpdater()

    private let calculator: Calculator
    private let file: URL
    private let download: @Sendable () async -> ExchangeRates?
    private let now: () -> Date
    private var isOn = false
    private var downloading: Task<Void, Never>?
    private(set) var rates: ExchangeRates?

    init(
        calculator: Calculator = .shared,
        file: URL = ExchangeRateStore.file,
        now: @escaping () -> Date = Date.init,
        download: @escaping @Sendable () async -> ExchangeRates? = { await ExchangeRateStore.download() }
    ) {
        self.calculator = calculator
        self.file = file
        self.now = now
        self.download = download
    }

    /// The switch changed, or the app started with it as it is.
    func set(on: Bool) {
        isOn = on
        guard on else {
            downloading?.cancel()
            downloading = nil
            rates = nil
            calculator.setExchangeRates([:])
            ExchangeRateStore.remove(file)
            return
        }
        if rates == nil, let stored = ExchangeRateStore.load(from: file) {
            rates = stored
            calculator.setExchangeRates(stored.rates, date: stored.date)
        }
        refreshIfStale()
    }

    /// Asks for new rates when there are none or they have aged. Called when the launcher opens, so a Mac
    /// left running gets the day's rates. The task is for a test to wait on.
    @discardableResult
    func refreshIfStale() -> Task<Void, Never>? {
        guard isOn, downloading == nil, rates?.isStale(at: now()) ?? true else { return downloading }
        let task = Task { [weak self, download] in
            let fresh = await download()
            guard let self, !Task.isCancelled else { return }
            downloading = nil
            guard let fresh, isOn else { return }
            rates = fresh
            ExchangeRateStore.save(fresh, to: file)
            calculator.setExchangeRates(fresh.rates, date: fresh.date)
        }
        downloading = task
        return task
    }
}
