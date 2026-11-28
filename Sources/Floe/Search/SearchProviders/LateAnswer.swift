//
//  LateAnswer.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Work a root search starts that answers after the list is shown. What it knows goes into the context, where a
/// LateSearchProvider reads it.
protocol LateAnswer: AnyObject {
    /// Whether the search field shows a spinner while this works.
    var showsProgress: Bool { get }
    /// Starts on the query, or keeps going when it is already on it. onChange runs each time the answer changes.
    func start(_ context: SearchContext, onChange: @escaping () -> Void)
    func cancel()
    /// Puts what is known so far into the context.
    func answer(into context: inout SearchContext)
    /// Waits for the work under way, for a test or the terminal search to read the finished answer.
    func settled() async
}

extension DefinitionSearch: LateAnswer {
    var showsProgress: Bool {
        isSearching
    }

    func start(_ context: SearchContext, onChange: @escaping () -> Void) {
        search(context, onChange: onChange)
    }

    func answer(into context: inout SearchContext) {
        context.definitions = definitions
    }
}

extension CalculatorSearch: LateAnswer {
    /// No spinner for the calculator: its answer is almost always a moment away.
    var showsProgress: Bool {
        false
    }

    func start(_ context: SearchContext, onChange: @escaping () -> Void) {
        search(context, onChange: onChange)
    }

    func answer(into context: inout SearchContext) {
        context.calculation = row
    }
}
