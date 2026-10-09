//
//  Contacts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Contacts
import Foundation

/// A person in the user's Contacts, as far as the search shows one: a name, and how to reach them.
nonisolated struct ContactPerson: Hashable, Sendable {
    /// What Contacts knows the card by.
    var identifier: String
    var name: String
    var phones: [String] = []
    var emails: [String] = []

    /// Beside the name: the first phone number, or the first email address.
    var detail: String? {
        phones.first ?? emails.first
    }
}

/// A row of the contacts scope.
enum ContactRow: Hashable {
    case person(ContactPerson)
    /// Stands in for the people after the user refused Floe the address book.
    case access

    var id: String {
        switch self {
        case let .person(person): "contact:\(person.identifier)"
        case .access: "contact-access"
        }
    }

    var title: String {
        switch self {
        case let .person(person): person.name
        case .access: String(localized: "Floe needs access to Contacts to find people", bundle: .floe, comment: "Contacts is the name of Apple's app and of a permission in System Settings.")
        }
    }
}

/// The links that reach a person, and the ones that open their card or the pane where access is given.
nonisolated enum ContactLinks {
    static let privacyPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")

    /// A number as a link carries it: the digits, a leading plus, and the star and hash of a keypad.
    static func dialable(_ phone: String) -> String {
        let kept = phone.filter { $0.isASCII && ($0.isNumber || "*#".contains($0)) }
        return phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" + kept : kept
    }

    static func card(_ person: ContactPerson) -> URL? {
        link("addressbook://", person.identifier)
    }

    static func call(_ phone: String) -> URL? {
        link("tel:", dialable(phone))
    }

    /// FaceTime and Messages reach a person by a number or by an email address.
    static func faceTime(_ address: String) -> URL? {
        link("facetime:", address.contains("@") ? address : dialable(address))
    }

    static func message(_ address: String) -> URL? {
        link("sms:", address.contains("@") ? address : dialable(address))
    }

    static func email(_ address: String) -> URL? {
        link("mailto:", address)
    }

    private static func link(_ scheme: String, _ value: String) -> URL? {
        value.isEmpty ? nil : URL(string: scheme + LinkText.escaped(value, keeping: "+*@"))
    }
}

/// The address book as the search reads it. Tests pass their own, so none reads the real one or asks for it.
nonisolated struct ContactBook: Sendable {
    /// Whether Floe may read contacts. macOS asks the user the first time.
    var requestAccess: @Sendable () async -> Bool
    /// Everyone in the address book. Blocks while it reads: call it off the main thread.
    var people: @Sendable () -> [ContactPerson]

    static let system = ContactBook(requestAccess: { await requestSystemAccess() }, people: { systemPeople() })

    private static func requestSystemAccess() async -> Bool {
        // Without the sentence that says why, macOS ends a process that asks: a development build run outside its bundle.
        guard Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") != nil else { return false }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return true
        case .notDetermined: return await (try? CNContactStore().requestAccess(for: .contacts)) ?? false
        default: return false
        }
    }

    private static func systemPeople() -> [ContactPerson] {
        let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var people: [ContactPerson] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            // A card with no name, such as a bare email address, has nothing to be found by.
            guard let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty else { return }
            people.append(ContactPerson(
                identifier: contact.identifier,
                name: name,
                phones: contact.phoneNumbers.map(\.value.stringValue),
                emails: contact.emailAddresses.map { $0.value as String }
            ))
        }
        return people
    }
}

nonisolated enum ContactSearch {
    static let limit = 30

    /// The people whose name holds every word of the query. A name or a word of it that starts with the query comes first.
    static func matching(_ people: [ContactPerson], query: String) -> [ContactPerson] {
        let wanted = folded(query)
        let words = wanted.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var starting: [ContactPerson] = []
        var holding: [ContactPerson] = []
        for person in people {
            let name = folded(person.name)
            guard words.allSatisfy(name.contains) else { continue }
            if name.hasPrefix(wanted) || name.contains(" " + wanted) {
                starting.append(person)
            } else {
                holding.append(person)
            }
        }
        return Array((starting + holding).prefix(limit))
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }
}

/// `contact ana`: the people in Contacts whose name matches. The address book is read off the main thread and kept for a minute.
struct ContactSearchScope: SearchScope {
    let keyword = "contact"
    let title = String(localized: "Contacts", bundle: .floe, comment: "A section title. Contacts are the people in Apple's Contacts app.")
    let emptyTitle = String(localized: "No contact matches", bundle: .floe)
    var book = ContactBook.system
    /// How long the people read stay in memory, so a name is not read for at each key.
    var lifetime: TimeInterval = 60
    var now: @Sendable () -> Date = { Date() }
    private let cache = TimedCache<Int, [ContactPerson]>()

    /// While the people read are fresh they answer at once.
    func results(for text: String, context _: SearchContext) -> [RootItem] {
        guard let people = cache.kept(for: 0, lasting: lifetime, now: now()) else { return [] }
        return rows(people, text: text)
    }

    /// Asks for access and reads the address book. Nil while `results` has the people.
    func updates(for text: String, context _: SearchContext) -> AsyncStream<[RootItem]>? {
        guard cache.kept(for: 0, lasting: lifetime, now: now()) == nil else { return nil }
        let (stream, continuation) = AsyncStream.makeStream(of: [RootItem].self)
        Task { @concurrent [book, cache, lifetime, now] in
            if await book.requestAccess() {
                let people = cache.value(for: 0, lasting: lifetime, now: now()) { book.people() }
                continuation.yield(ContactSearch.matching(people, query: text).map { RootItem.contact(.person($0)) })
            } else {
                continuation.yield([.contact(.access)])
            }
            continuation.finish()
        }
        return stream
    }

    private func rows(_ people: [ContactPerson], text: String) -> [RootItem] {
        ContactSearch.matching(people, query: text).map { RootItem.contact(.person($0)) }
    }
}
