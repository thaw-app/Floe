//
//  CalculatorSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The calculator's answer for the query on screen, worked out off the main thread so no row waits on fend's time limit.
/// Only the newest query waits its turn; those typed in between are never asked.
final class CalculatorSearch {
    typealias Evaluate = @concurrent @Sendable (String) async -> CalculationPreview?

    var evaluate: Evaluate
    /// The last answer the calculator gave, and the query it is for.
    private var answer: (query: String, preview: CalculationPreview?)?
    /// The query whose answer is wanted. Nil when none is.
    private var wanted: String?
    /// The row on screen, kept while the next query is worked out so it does not leave and come back with each key.
    private var lastRow: CalculatorRow?
    private var onChange: () -> Void = {
        // Nothing on screen yet.
    }

    private var task: Task<Void, Never>?

    init(evaluate: @escaping Evaluate = { Calculator.shared.evaluatePreview($0) }) {
        self.evaluate = evaluate
    }

    deinit {
        task?.cancel()
    }

    /// The row for the query on screen: its own answer once that is known, and until then the row before it.
    var row: CalculatorRow? {
        guard let wanted else { return nil }
        guard let answer, answer.query == wanted else { return lastRow }
        return answer.preview.map { CalculatorRow(expression: wanted, preview: $0) }
    }

    func search(_ context: SearchContext, onChange: @escaping () -> Void) {
        guard !context.query.isEmpty else {
            cancel()
            return
        }
        guard context.query != wanted else { return }
        wanted = context.query
        self.onChange = onChange
        if task == nil {
            task = Task { [weak self] in await self?.work() }
        }
    }

    private func work() async {
        while let query = wanted, answer?.query != query {
            let preview = await evaluate(query)
            guard !Task.isCancelled else { break }
            answer = (query, preview)
            // A query typed past while it was worked out is answered and dropped: the newest is asked next.
            guard query == wanted else { continue }
            lastRow = preview.map { CalculatorRow(expression: query, preview: $0) }
            onChange()
        }
        task = nil
    }

    func cancel() {
        wanted = nil
        lastRow = nil
    }

    func settled() async {
        await task?.value
    }
}

/// What the calculator's row shows: the expression it answers and the answer.
struct CalculatorRow {
    let expression: String
    let preview: CalculationPreview
}
