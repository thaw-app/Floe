//
//  Model+Contacts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// People from Contacts, as the launcher opens and reaches them.
extension LauncherModel {
    /// Return on a person opens their card in Contacts. On the row that stands in for them, the pane where access is given.
    func open(_ row: ContactRow) {
        switch row {
        case let .person(person): reach(ContactLinks.card(person))
        case .access: reach(ContactLinks.privacyPane)
        }
    }

    /// The Actions menu of a person, after Open in Contacts: a way to reach them for each thing their card has.
    func contactActions(for person: ContactPerson) -> [ItemAction?] {
        let reaching = person.phones.first ?? person.emails.first
        var actions: [ItemAction?] = [nil]
        if let phone = person.phones.first {
            actions.append(ItemAction(title: String(localized: "Call", bundle: .floe, comment: "A verb on a button: phone the person."), symbol: "phone") { [weak self] in self?.reach(ContactLinks.call(phone)) })
        }
        if let reaching {
            actions.append(ItemAction(title: "FaceTime", symbol: "video") { [weak self] in self?.reach(ContactLinks.faceTime(reaching)) })
            actions.append(ItemAction(title: String(localized: "Message", bundle: .floe, comment: "A verb on a button: write the person a message."), symbol: "message") { [weak self] in self?.reach(ContactLinks.message(reaching)) })
        }
        if let email = person.emails.first {
            actions.append(ItemAction(title: String(localized: "Email", bundle: .floe, comment: "A verb on a button: write the person an email."), symbol: "envelope") { [weak self] in self?.reach(ContactLinks.email(email)) })
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

    /// Opens a link through the system once the panel is gone. A link that could not be made opens nothing.
    func reach(_ link: URL?) {
        hidePanel()
        reset()
        if let link {
            linkOpener.open(link, nil)
        }
    }

    private func copyContactDetail(_ text: String) {
        NSPasteboard.general.copy(text)
        showHUD(String(localized: "Copied \(text)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
    }
}
