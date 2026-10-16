//
//  ContactRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// People from Contacts, and drafts of an email or a message to someone, as the launcher opens and reaches them.
final class ContactRows {
    var host = RowHost()

    /// Return on a person opens their card in Contacts. On the row that stands in for them, the pane where access is given.
    func open(_ row: ContactRow) {
        switch row {
        case let .person(person): host.reach(ContactLinks.card(person))
        case .access: host.reach(ContactLinks.privacyPane)
        }
    }

    /// The Actions menu of a person, after Open in Contacts: a way to reach them for each thing their card has.
    func contactActions(for person: ContactPerson) -> [ItemAction?] {
        let reaching = person.phones.first ?? person.emails.first
        var actions: [ItemAction?] = [nil]
        if let phone = person.phones.first {
            actions.append(ItemAction(title: String(localized: "Call", bundle: .floe, comment: "A verb on a button: phone the person."), symbol: "phone") { [weak self] in self?.host.reach(ContactLinks.call(phone)) })
        }
        if let reaching {
            actions.append(ItemAction(title: "FaceTime", symbol: "video") { [weak self] in self?.host.reach(ContactLinks.faceTime(reaching)) })
            actions.append(ItemAction(title: String(localized: "Message", bundle: .floe, comment: "A verb on a button: write the person a message."), symbol: "message") { [weak self] in self?.host.reach(ContactLinks.message(reaching)) })
        }
        if let email = person.emails.first {
            actions.append(ItemAction(title: String(localized: "Email", bundle: .floe, comment: "A verb on a button: write the person an email."), symbol: "envelope") { [weak self] in self?.host.reach(ContactLinks.email(email)) })
        }
        actions.append(nil)
        if let phone = person.phones.first {
            actions.append(ItemAction(title: String(localized: "Copy Phone", bundle: .floe), symbol: "doc.on.doc") { [weak self] in self?.copyContactDetail(phone) })
        }
        if let email = person.emails.first {
            actions.append(ItemAction(title: String(localized: "Copy Email", bundle: .floe), symbol: "doc.on.doc") { [weak self] in self?.copyContactDetail(email) })
        }
        // A card with nothing to reach it by leaves the separators with nothing between them.
        while case .some(.none) = actions.last {
            actions.removeLast()
        }
        return actions
    }

    private func copyContactDetail(_ text: String) {
        NSPasteboard.general.copy(text)
        host.showHUD(String(localized: "Copied \(text)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
    }
}

extension ContactRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        switch item {
        case .contact(.person): String(localized: "Open in Contacts", bundle: .floe, comment: "Contacts is the name of Apple's app.")
        case .contact(.access): String(localized: "Open Privacy Settings", bundle: .floe, comment: "A button that opens the Privacy pane of System Settings.")
        case .outgoing: String(localized: "Open Draft", bundle: .floe, comment: "A button that opens a new email or message with the text filled in. Nothing is sent.")
        default: nil
        }
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        switch item {
        case let .contact(row): open(row)
        case let .outgoing(draft): host.reach(draft.link)
        default: return false
        }
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .contact(.person(person)) = item else { return nil }
        return contactActions(for: person)
    }
}
