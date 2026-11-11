//
//  ReceiptsSearchScope.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// `receipts`: what Floe did lately, newest first, and with some text the ones that mention it.
struct ReceiptsSearchScope: SearchScope {
    static let limit = 50

    nonisolated static let word = "receipts"

    let keyword = Self.word
    let title = String(localized: "Receipts", bundle: .floe)
    let emptyTitle = String(localized: "No receipts yet", bundle: .floe)
    var receipts: @Sendable () -> [Receipt] = { ReceiptStore.shared.all }

    /// The word alone lists everything, as `ssh` and a space lists every host.
    func text(in context: SearchContext) -> String? {
        context.text(afterOrAlone: keyword)
    }

    func results(for text: String, context _: SearchContext) -> [RootItem] {
        let words = TypedWords(text)
        return receipts()
            .filter { words.areAll(in: "\($0.title) \($0.detail)") }
            .prefix(Self.limit).map(RootItem.receipt)
    }
}
