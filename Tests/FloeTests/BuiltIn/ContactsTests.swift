//
//  ContactsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// What stands in for the address book: made-up people, and a count of what was asked of it.
private final nonisolated class Stand: Sendable {
    struct State {
        var isAllowed = true
        var asked = 0
        var read = 0
        var readOnMain: Bool?
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var opened: [String] = []
    }

    let state = Mutex(State())

    static let ana = ContactPerson(identifier: "A1:ABPerson", name: "Ana García", phones: ["+34 600 11 22 33", "915 55 01 01"], emails: ["ana@example.com"])
    static let mariana = ContactPerson(identifier: "M2:ABPerson", name: "Mariana Ruiz", emails: ["mariana@example.com", "m.ruiz@example.org"])
    static let toni = ContactPerson(identifier: "T3:ABPerson", name: "Toni Anaya", phones: ["(555) 123-4567"])
    static let studio = ContactPerson(identifier: "S4:ABPerson", name: "Estudio Luz")
    static let people = [mariana, toni, ana, studio]

    var book: ContactBook {
        ContactBook(
            requestAccess: { [self] in
                state.withLock {
                    $0.asked += 1
                    return $0.isAllowed
                }
            },
            people: { [self] in
                state.withLock {
                    $0.read += 1
                    $0.readOnMain = Thread.isMainThread
                }
                return Self.people
            }
        )
    }

    var scope: ContactSearchScope {
        ContactSearchScope(book: book, now: { [self] in state.withLock { $0.now } })
    }

    var opener: LinkOpener {
        LinkOpener { [self] url, _ in state.withLock { $0.opened.append(url.absoluteString) } }
    }

    var asked: Int {
        state.withLock { $0.asked }
    }

    var read: Int {
        state.withLock { $0.read }
    }

    var opened: [String] {
        state.withLock { $0.opened }
    }
}

@MainActor
struct ContactsTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-contacts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A model whose only scope reads the stand-in, and whose links go to it instead of being opened.
    private func model(in folder: URL, stand: Stand) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-contacts-\(UUID().uuidString)")!
        let model = LauncherModel(
            settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []),
            scopes: [stand.scope], sources: []
        )
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.linkOpener = stand.opener
        return model
    }

    /// Every batch a scope delivers for a query, as the titles of its rows.
    private func delivered(_ scope: ContactSearchScope, _ text: String) async -> [[String]]? {
        guard let stream = scope.updates(for: text, context: SearchContext(query: "contact \(text)")) else { return nil }
        var batches: [[String]] = []
        for await rows in stream {
            batches.append(rows.map(\.title))
        }
        return batches
    }

    private func settle(_ model: LauncherModel) async {
        for _ in 0 ..< 200 where model.isAwaitingResults {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Matching

    @Test func aNameIsFoundByItsWordsAndOneThatStartsWithThemComesFirst() {
        let found: (String) -> [String] = { ContactSearch.matching(Stand.people, query: $0).map(\.name) }
        #expect(found("ana") == ["Toni Anaya", "Ana García", "Mariana Ruiz"])
        #expect(found("ANA g") == ["Ana García"])
        #expect(found("garcia") == ["Ana García"], "an accent is not needed")
        #expect(found("ruiz mari") == ["Mariana Ruiz"], "the words in any order")
        #expect(found("luz") == ["Estudio Luz"])
        #expect(found("zoe").isEmpty)
        #expect(found("  ").isEmpty)
        #expect(found("ana@example.com").isEmpty, "people are found by name")

        let many = (1 ... 40).map { ContactPerson(identifier: "\($0)", name: "Ana \($0)") }
        #expect(ContactSearch.matching(many, query: "ana").count == ContactSearch.limit)
    }

    // MARK: Links

    @Test func theLinksCarryANumberOrAnAddress() {
        #expect(ContactLinks.dialable("+34 600 11 22 33") == "+34600112233")
        #expect(ContactLinks.dialable("(555) 123-4567") == "5551234567")
        #expect(ContactLinks.dialable("*123#") == "*123#")
        #expect(ContactLinks.call("+34 600 11 22 33")?.absoluteString == "tel:+34600112233")
        #expect(ContactLinks.call("*123#")?.absoluteString == "tel:*123%23")
        #expect(ContactLinks.call("no number") == nil)
        #expect(ContactLinks.faceTime("(555) 123-4567")?.absoluteString == "facetime:5551234567")
        #expect(ContactLinks.faceTime("ana@example.com")?.absoluteString == "facetime:ana@example.com")
        #expect(ContactLinks.message("+34 600 11 22 33")?.absoluteString == "sms:+34600112233")
        #expect(ContactLinks.message("ana@example.com")?.absoluteString == "sms:ana@example.com")
        #expect(ContactLinks.email("ana+work@example.com")?.absoluteString == "mailto:ana+work@example.com")
        #expect(ContactLinks.email("a b?c&d@example.com")?.absoluteString == "mailto:a%20b%3Fc%26d@example.com")
        #expect(ContactLinks.card(Stand.ana)?.absoluteString == "addressbook://A1%3AABPerson")
        #expect(ContactLinks.privacyPane?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")
    }

    // MARK: The rows

    @Test func aPersonShowsTheFirstPhoneOrEmailBesideTheName() {
        let row = RootItem.contact(.person(Stand.ana))
        #expect(row.title == "Ana García")
        #expect(row.rowLabel == "+34 600 11 22 33")
        #expect(row.id == "contact:A1:ABPerson")
        #expect(row.kind == "Contact")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(row))
        #expect(RootItem.contact(.person(Stand.mariana)).rowLabel == "mariana@example.com")
        #expect(RootItem.contact(.person(Stand.studio)).rowLabel == "Contact")

        let access = RootItem.contact(.access)
        #expect(access.title == "Floe needs access to Contacts to find people")
        #expect(access.id == "contact-access")
        #expect(access.rowLabel == "Contact")
        #expect(access.isScopeResult)
    }

    // MARK: The scope

    @Test func theKeywordAloneOrAnotherWordIsAnOrdinarySearch() {
        let scope = Stand().scope
        #expect(scope.text(in: SearchContext(query: "contact ana")) == "ana")
        #expect(scope.text(in: SearchContext(query: "Contact  Ana G")) == "Ana G")
        #expect(scope.text(in: SearchContext(query: "contact")) == nil)
        #expect(scope.text(in: SearchContext(query: "contact ")) == nil)
        #expect(scope.text(in: SearchContext(query: "contacts ana")) == nil)
        #expect(scope.text(in: SearchContext(query: "ana contact")) == nil)
        let standard = RootSearch.standardScopes().map(\.keyword)
        #expect(standard.contains("contact"))
    }

    @Test func thePeopleAreReadOffTheMainThreadAndKeptForAMinute() async {
        let stand = Stand()
        let scope = stand.scope
        #expect(scope.results(for: "ana", context: SearchContext(query: "contact ana")).isEmpty, "nothing is known at once")
        #expect(stand.asked == 0)
        #expect(stand.read == 0)

        #expect(await delivered(scope, "ana") == [["Toni Anaya", "Ana García", "Mariana Ruiz"]])
        #expect(stand.asked == 1)
        #expect(stand.read == 1)
        #expect(stand.state.withLock { $0.readOnMain } == false)

        #expect(scope.results(for: "mari", context: SearchContext(query: "contact mari")).map(\.title) == ["Mariana Ruiz"], "the next key is answered from memory")
        #expect(await delivered(scope, "mari") == nil)
        #expect(stand.read == 1)

        stand.state.withLock { $0.now += 59 }
        #expect(await delivered(scope, "toni") == nil)
        stand.state.withLock { $0.now += 2 }
        #expect(scope.results(for: "toni", context: SearchContext(query: "contact toni")).isEmpty, "a minute on, the people are read again")
        #expect(await delivered(scope, "toni") == [["Toni Anaya"]])
        #expect(stand.read == 2)
    }

    @Test func refusedAccessShowsOneRowThatSaysSoAndReadsNothing() async {
        let stand = Stand()
        stand.state.withLock { $0.isAllowed = false }
        let scope = stand.scope
        #expect(await delivered(scope, "ana") == [["Floe needs access to Contacts to find people"]])
        #expect(stand.read == 0)
        #expect(scope.results(for: "ana", context: SearchContext(query: "contact ana")).isEmpty)
        #expect(await delivered(scope, "an") == [["Floe needs access to Contacts to find people"]], "nothing is kept of a refusal, so allowing it later is noticed")
    }

    // MARK: The launcher

    @Test func accessIsAskedOnlyForTheKeywordAndSomeText() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        for query in ["ana", "con", "contact", "contact ", "contacts ana", "call ana"] {
            model.query = query
            await settle(model)
        }
        #expect(stand.asked == 0)
        #expect(stand.read == 0)

        model.query = "contact ana"
        await settle(model)
        #expect(stand.asked == 1)
        #expect(model.results.map(\.item.title) == ["Toni Anaya", "Ana García", "Mariana Ruiz"])
        #expect(model.results.map(\.item.rowLabel) == ["(555) 123-4567", "+34 600 11 22 33", "mariana@example.com"])
        #expect(model.results.compactMap(\.section).first == "Contacts")

        model.query = "contact ana g"
        #expect(model.results.map(\.item.title) == ["Ana García"], "shown at once from the people in memory")
        #expect(!model.isAwaitingResults)
        #expect(stand.asked == 1)
    }

    @Test func returnOpensThePersonInContactsAndTheMenuReachesThem() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var hidden = 0
        model.hidePanel = { hidden += 1 }
        let titles: (ContactPerson) -> [String] = { person in model.rootActions(for: .contact(.person(person))).map { $0?.title ?? "-" } }

        let row = RootItem.contact(.person(Stand.ana))
        #expect(model.primaryActionTitle(for: row) == "Open in Contacts")
        #expect(titles(Stand.ana) == ["Open in Contacts", "-", "Call", "FaceTime", "Message", "Email", "-", "Copy Phone", "Copy Email"])
        #expect(titles(Stand.mariana) == ["Open in Contacts", "-", "FaceTime", "Message", "Email", "-", "Copy Email"])
        #expect(titles(Stand.toni) == ["Open in Contacts", "-", "Call", "FaceTime", "Message", "-", "Copy Phone"])
        #expect(titles(Stand.studio) == ["Open in Contacts"], "a card with only a name has nothing to reach it by")

        model.activate(row)
        #expect(stand.opened == ["addressbook://A1%3AABPerson"])
        #expect(hidden == 1)
        #expect(model.receipts.all.isEmpty)

        for title in ["Call", "FaceTime", "Message", "Email"] {
            let action = try #require(model.rootActions(for: row).compactMap(\.self).first { $0.title == title })
            action.run()
        }
        #expect(stand.opened.dropFirst() == ["tel:+34600112233", "facetime:+34600112233", "sms:+34600112233", "mailto:ana@example.com"])
        let byMail = model.rootActions(for: .contact(.person(Stand.mariana))).compactMap(\.self)
        try #require(byMail.first { $0.title == "Message" }).run()
        #expect(stand.opened.last == "sms:mariana@example.com")
    }

    @Test func returnOnTheRefusalOpensThePrivacyPane() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.state.withLock { $0.isAllowed = false }
        let model = model(in: folder, stand: stand)
        model.query = "contact ana"
        await settle(model)
        let row = try #require(model.results.first?.item)
        #expect(model.results.count == 1)
        #expect(row.id == "contact-access")
        #expect(model.primaryActionTitle(for: row) == "Open Privacy Settings")
        #expect(model.rootActions(for: row).compactMap { $0?.title } == ["Open Privacy Settings"])

        model.activate(row)
        #expect(stand.opened == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"])
    }

    @Test func theCacheAnswersOnlyWithWhatItKeeps() {
        let cache = TimedCache<String, Int>()
        let start = Date(timeIntervalSince1970: 1000)
        #expect(cache.kept(for: "a") == nil)
        #expect(cache.value(for: "a", lasting: 2, now: start) { 7 } == 7)
        #expect(cache.kept(for: "a", lasting: 2, now: start.addingTimeInterval(1.9)) == 7)
        #expect(cache.kept(for: "a", lasting: 2, now: start.addingTimeInterval(2.1)) == nil)
        #expect(cache.kept(for: "b") == nil)
    }
}
