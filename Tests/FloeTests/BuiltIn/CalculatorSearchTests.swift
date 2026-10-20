//
//  CalculatorSearchTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// An evaluation that answers each query with itself, and holds the first one until the test lets it go.
private final nonisolated class HeldCalculator: Sendable {
    let asked = Mutex<[String]>([])
    let began: AsyncStream<Void>
    private let beginning: AsyncStream<Void>.Continuation
    private let release = DispatchSemaphore(value: 0)

    init() {
        (began, beginning) = AsyncStream.makeStream(of: Void.self)
    }

    func evaluate(_ query: String) -> CalculationPreview? {
        let isFirst = asked.withLock {
            $0.append(query)
            return $0.count == 1
        }
        if isFirst {
            beginning.yield()
            release.wait()
        }
        return query.hasPrefix("1") ? CalculationPreview(result: "= \(query)") : nil
    }

    func letGo() {
        release.signal()
    }
}

@MainActor struct CalculatorSearchTests {
    @Test func onlyTheQueryTypedLastWaitsForTheOneBeingWorkedOut() async {
        let held = HeldCalculator()
        let search = CalculatorSearch { held.evaluate($0) }
        var changes = 0
        search.search(SearchContext(query: "1")) { changes += 1 }
        var began = held.began.makeAsyncIterator()
        await began.next()
        search.search(SearchContext(query: "12")) { changes += 1 }
        search.search(SearchContext(query: "123")) { changes += 1 }
        #expect(search.row == nil, "no answer yet")
        held.letGo()
        await search.settled()
        #expect(held.asked.withLock { $0 } == ["1", "123"], "the query typed past is never asked")
        #expect(search.row?.expression == "123")
        #expect(search.row?.preview.result == "= 123")
        #expect(changes == 1, "the answer for a query typed past is not shown")
    }

    @Test func theRowStaysWhileTheNextQueryIsWorkedOutAndGoesWhenItHasNoAnswer() async {
        let search = CalculatorSearch { $0.hasPrefix("1") ? CalculationPreview(result: "= \($0)") : nil }
        search.search(SearchContext(query: "1+1")) {}
        await search.settled()
        #expect(search.row?.expression == "1+1")
        search.search(SearchContext(query: "1+1 apples")) {}
        #expect(search.row?.expression == "1+1", "the row before it, until the answer comes")
        await search.settled()
        #expect(search.row?.expression == "1+1 apples")
        search.search(SearchContext(query: "safari")) {}
        await search.settled()
        #expect(search.row == nil)
        search.search(SearchContext(query: "")) {}
        #expect(search.row == nil)
    }

    @Test func theLauncherShowsTheAnswerWhenItArrives() async {
        let model = LauncherModel(settings: AppSettings(defaults: MemoryDefaults()), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        model.query = "6*7"
        await model.calculatorSearch.settled()
        #expect(model.results.first?.id == "calculator")
        #expect(model.results.first?.item.title.contains("42") == true)
        #expect(model.selection == 0)
    }
}
