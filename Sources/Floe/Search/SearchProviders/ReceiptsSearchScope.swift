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

    let keyword = "receipts"
    let title = String(localized: "Receipts", bundle: .floe)
    let emptyTitle = String(localized: "No receipts yet", bundle: .floe)
    var receipts: @Sendable () -> [Receipt] = { ReceiptStore.shared.all }

    /// The word alone lists everything, as `ssh` and a space lists every host.
    func text(in context: SearchContext) -> String? {
        if let text = context.text(after: keyword) {
            return text
        }
        return context.trimmed.lowercased() == keyword ? "" : nil
    }

    func results(for text: String, context _: SearchContext) -> [RootItem] {
        let words = text.lowercased().split(separator: " ")
        return receipts()
            .filter { receipt in words.allSatisfy { "\(receipt.title) \(receipt.detail)".lowercased().contains($0) } }
            .prefix(Self.limit).map(RootItem.receipt)
    }
}
