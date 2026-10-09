//
//  OutgoingDrafts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What `mail` or `message` and some text asks for: a draft in the mail or the messages app. Nothing is sent.
nonisolated struct OutgoingDraft: Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case mail, message

        /// The word that starts the request.
        var keyword: String {
            rawValue
        }
    }

    var kind: Kind
    /// An email address for mail, a phone number for a message. Nil when the text starts with neither.
    var recipient: String?
    /// Everything typed after the keyword and the recipient.
    var text: String

    /// `mail toni@example.com the build is ready` is a draft to Toni; without an address first, the whole text is the body.
    static func request(in query: String) -> OutgoingDraft? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = query.firstIndex(of: " "), let kind = Kind(rawValue: query[..<space].lowercased()) else { return nil }
        let rest = query[space...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        let end = rest.firstIndex(where: \.isWhitespace) ?? rest.endIndex
        let first = String(rest[..<end])
        guard kind == .mail ? isEmailAddress(first) : isPhoneNumber(first) else { return OutgoingDraft(kind: kind, recipient: nil, text: rest) }
        return OutgoingDraft(kind: kind, recipient: first, text: rest[end...].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isEmailAddress(_ word: String) -> Bool {
        word.wholeMatch(of: #/[^\s@]+@[^\s@]+\.[^\s@.]+/#) != nil
    }

    /// Digits with the marks numbers are written with. Five digits at least, or three after a plus, so "message 2 minutes late" has no recipient.
    static func isPhoneNumber(_ word: String) -> Bool {
        guard word.wholeMatch(of: #/\+?\d[\d().\-]*/#) != nil else { return false }
        return word.count(where: \.isNumber) >= (word.hasPrefix("+") ? 3 : 5)
    }

    private var lines: [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The first line, when there is more than one. A single line is all body.
    var subject: String? {
        lines.count > 1 ? lines.first : nil
    }

    /// The text without the line that became the subject.
    var body: String {
        subject == nil ? text : lines.dropFirst().joined(separator: "\n")
    }

    /// The link that opens the draft. Messages has no subject, so there the whole text is the body.
    var link: URL? {
        switch kind {
        case .mail: URL(string: DraftLinks.mail(to: recipient, subject: subject, body: body))
        case .message: URL(string: DraftLinks.message(to: recipient, body: text))
        }
    }

    var title: String {
        guard let line = lines.first else {
            let recipient = recipient ?? ""
            return kind == .mail
                ? String(localized: "Mail to \(recipient)", bundle: .floe, comment: "The title of the row that opens an empty email draft. The placeholder is an email address.")
                : String(localized: "Message to \(recipient)", bundle: .floe, comment: "The title of the row that opens an empty message draft. The placeholder is a phone number.")
        }
        return kind == .mail
            ? String(localized: "Mail: \(line)", bundle: .floe, comment: "The title of the row that opens an email draft. The placeholder is the first line of what was typed.")
            : String(localized: "Message: \(line)", bundle: .floe, comment: "The title of the row that opens a message draft. The placeholder is the first line of what was typed.")
    }

    /// Beside the title: who it goes to. Nil when the title already says.
    var label: String? {
        guard !lines.isEmpty else { return nil }
        return recipient ?? String(localized: "No recipient", bundle: .floe, comment: "Beside a mail or message draft whose text names nobody to send it to.")
    }
}

/// The links that open a draft. Everything outside letters, digits and four marks is escaped, so no character of the text ends the link early.
nonisolated enum DraftLinks {
    /// `mailto:` with the address, then the subject and the body. A line break travels as a carriage return and a line feed, as mail writes one.
    static func mail(to recipient: String?, subject: String?, body: String) -> String {
        var fields: [String] = []
        if let subject, !subject.isEmpty {
            fields.append("subject=" + LinkText.escaped(subject))
        }
        if !body.isEmpty {
            fields.append("body=" + LinkText.escaped(body.replacing(#/\r\n|\r|\n/#, with: "\r\n")))
        }
        let address = LinkText.escaped(recipient ?? "", keeping: "@+")
        return "mailto:" + address + (fields.isEmpty ? "" : "?" + fields.joined(separator: "&"))
    }

    /// `sms:` with the number, then the body after an ampersand, which is how Messages reads one.
    static func message(to recipient: String?, body: String) -> String {
        let number = LinkText.escaped(ContactLinks.dialable(recipient ?? ""), keeping: "+")
        return "sms:" + number + (body.isEmpty ? "" : "&body=" + LinkText.escaped(body))
    }
}

/// `mail` or `message` and some text leads the results with the row that opens the draft.
struct OutgoingDraftSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard OutgoingDraft.Kind.allCases.contains(where: { context.text(after: $0.keyword) != nil }), let draft = OutgoingDraft.request(in: context.trimmed) else { return SearchContribution() }
        let row = RootResult(item: .outgoing(draft), section: nil)
        // Something of the user's whose name starts with what was typed keeps the lead, such as a shortcut called Mail Me the News.
        return isTheStartOfAName(context) ? SearchContribution(appended: [row]) : SearchContribution(pinned: [row])
    }

    private func isTheStartOfAName(_ context: SearchContext) -> Bool {
        let typed = context.trimmed.lowercased()
        let names = context.apps.map(\.name) + context.commands.map(\.title) + context.scripts.map(\.title) + context.shortcuts.map(\.name)
        return names.contains { $0.lowercased().hasPrefix(typed) }
    }
}
