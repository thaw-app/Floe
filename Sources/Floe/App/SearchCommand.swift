//
//  SearchCommand.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The command-line search waits for the local dictionary and the calculator, but never starts browser or file sources.
func runSearch(query: String) -> Never {
    let model = LauncherModel(snapshot: .scanningNow(includeRaycast: AppSettings.shared.includeRaycastExtensions), sources: [])
    model.canAskAI = { AIAnswer.isAvailable }
    model.query = query
    Task { @MainActor in
        await model.definitionSearch.settled()
        await model.calculatorSearch.settled()
        for result in model.results.prefix(8) {
            print("\(result.section.map { "[\($0)] " } ?? "")\(result.item.title) (\(result.item.kind))\(model.alias(for: result.item).map { " (alias \($0))" } ?? "")")
        }
        exit(0)
    }
    RunLoop.main.run()
    exit(1)
}
