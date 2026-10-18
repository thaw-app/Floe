//
//  FoundRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Rows the search worked out from what was typed: keywords, dictionary definitions, answers, bookmarks and
/// the calculator's result.
final class FoundRows {
    var host = RowHost()
    /// Puts text into the search field, ready for the rest to be typed after it.
    var typeQuery: (String) -> Void = { _ in }
    /// Where Return copies to. Tests replace it, so they leave the clipboard alone.
    var pasteboard = NSPasteboard.general

    /// Return on an answer: a link opens, anything else goes to the clipboard, a password marked so that
    /// clipboard managers leave it alone.
    private func open(_ answer: AnswerRow) {
        if let link = answer.link {
            host.reach(link)
            return
        }
        if answer.isSecret {
            pasteboard.copySecret(answer.text)
        } else {
            pasteboard.copy(answer.text)
        }
        host.showHUD(String(localized: "Copied Answer", bundle: .floe))
        host.leave()
    }

    /// What the dictionary says about the word goes to the clipboard.
    private func copy(_ definition: WordDefinition) {
        pasteboard.copy(definition.text)
        host.showHUD(String(localized: "Copied \(definition.word)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
        host.leave()
    }

    /// Return on the calculator's row: the answer goes to the clipboard. With no answer the row is still the
    /// selected one, so Return says what is wrong, or that there is nothing yet.
    private func copyCalculation(_ result: String, error: String?) {
        guard error == nil, !result.isEmpty else {
            host.showHUD(error ?? String(localized: "Nothing to copy yet", bundle: .floe, comment: "Shown when Return is pressed on a calculation that has no answer."))
            return
        }
        pasteboard.copy(result)
        host.showHUD(String(localized: "Copied \(result)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
        host.leave()
    }
}

extension FoundRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        switch item {
        case .keyword:
            String(localized: "Type Keyword", bundle: .floe, comment: "A button that puts the selected keyword into the search field, for the user to go on typing.")
        case .definition:
            String(localized: "Open in Dictionary", bundle: .floe, comment: "Dictionary is the name of Apple's app.")
        case let .answer(row) where row.link == nil:
            String(localized: "Copy to Clipboard", bundle: .floe)
        case let .answer(row):
            row.linkTitle ?? String(localized: "Open", bundle: .floe, comment: "A verb on a button: open the selected result.")
        default: nil
        }
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case let .keyword(hint): typeQuery(hint.typed)
        case let .definition(definition): host.reach(definition.link)
        case let .answer(row): open(row)
        case let .bookmark(bookmark): host.reach(bookmark.url)
        case let .calculator(_, result, error, _): copyCalculation(result, error: error)
        default: return false
        }
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .definition(definition) = item else { return nil }
        return [ItemAction(title: String(localized: "Copy Definition", bundle: .floe), symbol: "doc.on.doc") { [weak self] in self?.copy(definition) }]
    }
}
