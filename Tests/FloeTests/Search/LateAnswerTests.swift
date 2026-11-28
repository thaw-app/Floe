//
//  LateAnswerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

/// The calculator and the dictionary as the late answers the root search starts, read and cancels alike.
@MainActor
struct LateAnswerTests {
    @Test func theCalculatorPutsItsRowInTheContextAndShowsNoSpinner() async {
        let late: any LateAnswer = CalculatorSearch(evaluate: { CalculationPreview(result: "= \($0)") })
        var changes = 0
        late.start(SearchContext(query: "1+1")) { changes += 1 }
        #expect(!late.showsProgress, "its answer is almost always a moment away")
        await late.settled()
        var context = SearchContext(query: "1+1")
        late.answer(into: &context)
        #expect(context.calculation?.expression == "1+1")
        #expect(changes == 1)

        late.cancel()
        late.answer(into: &context)
        #expect(context.calculation == nil)
    }

    @Test func theDictionaryShowsASpinnerUntilItsEntriesAreIn() async {
        let late: any LateAnswer = DefinitionSearch(lookup: { "the entry for \($0)" }, completions: { _ in [] })
        late.start(SearchContext(query: "define tide")) {
            // Read once settled below.
        }
        #expect(late.showsProgress)
        await late.settled()
        #expect(!late.showsProgress)
        var context = SearchContext(query: "define tide")
        late.answer(into: &context)
        #expect(context.definitions.map(\.word) == ["tide"])

        late.cancel()
        late.answer(into: &context)
        #expect(context.definitions.isEmpty)
    }
}
