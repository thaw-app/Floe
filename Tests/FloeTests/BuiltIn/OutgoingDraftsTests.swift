//
//  OutgoingDraftsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// What a test's opener was asked to open, in place of opening it. Only the main actor touches it.
private final nonisolated class Opened: @unchecked Sendable {
    var links: [String] = []

    var opener: LinkOpener {
        LinkOpener { [self] url, _ in links.append(url.absoluteString) }
    }
}

@MainActor
struct OutgoingDraftsTests {
    /// Text with every character that could end a link early or be read as something else.
    private static nonisolated let awkward = "Q&A? yes + no = 100% #1\nsecond line; ok/fine: \"quoted\" ñ ☕"

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-drafts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A model whose links go to the test instead of being opened.
    private func model(in folder: URL, opened: Opened) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-drafts-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: [])
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.linkOpener = opened.opener
        return model
    }

    /// The fields of a `mailto:` link as the mail app reads them back.
    private func fields(_ link: String) throws -> [String: String] {
        let items = try #require(URLComponents(string: link)).queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    // MARK: Reading the text

    @Test(arguments: [
        ("mail toni@example.com the build is ready", "toni@example.com", "the build is ready"),
        ("mail the build is ready", nil, "the build is ready"),
        ("Mail  Toni@Example.com   the build", "Toni@Example.com", "the build"),
        ("mail toni@example.com", "toni@example.com", ""),
        ("mail toni+floe@mail.example.co.uk hi", "toni+floe@mail.example.co.uk", "hi"),
        ("mail write to toni@example.com today", nil, "write to toni@example.com today"),
        ("mail @toni see this", nil, "@toni see this"),
        ("mail toni@example hi", nil, "toni@example hi"),
        ("mail toni@example. hi", nil, "toni@example. hi"),
        ("mail +15551234567 call me", nil, "+15551234567 call me"),
    ])
    func mailTakesAnAddressFirstAsTheRecipient(query: String, recipient: String?, text: String) {
        #expect(OutgoingDraft.request(in: query) == OutgoingDraft(kind: .mail, recipient: recipient, text: text))
    }

    @Test(arguments: [
        ("message +15551234567 running late", "+15551234567", "running late"),
        ("message running late", nil, "running late"),
        ("message 555-123-4567 running late", "555-123-4567", "running late"),
        ("message (555)123-4567 hi", nil, "(555)123-4567 hi"),
        ("MESSAGE 5551234567", "5551234567", ""),
        ("message +34600112233 llego tarde", "+34600112233", "llego tarde"),
        ("message 2 minutes late", nil, "2 minutes late"),
        ("message 2024 was a good year", nil, "2024 was a good year"),
        ("message +1 for that", nil, "+1 for that"),
        ("message toni@example.com hi", nil, "toni@example.com hi"),
        ("message 555-CALL-NOW hi", nil, "555-CALL-NOW hi"),
    ])
    func messageTakesANumberFirstAsTheRecipient(query: String, recipient: String?, text: String) {
        #expect(OutgoingDraft.request(in: query) == OutgoingDraft(kind: .message, recipient: recipient, text: text))
    }

    @Test(arguments: ["mail", "mail ", "message", "message  ", "mailbox full", "messages hi", "email toni@example.com hi", "hi mail", "sms hi"])
    func anythingElseIsAnOrdinarySearch(query: String) {
        #expect(OutgoingDraft.request(in: query) == nil)
        #expect(OutgoingDraftSearchProvider().contribution(for: SearchContext(query: query)).pinned.isEmpty)
    }

    @Test func theFirstLineIsTheSubjectOnlyWhenThereAreMoreLines() {
        let one = OutgoingDraft(kind: .mail, recipient: nil, text: "the build is ready. Ship it.")
        #expect(one.subject == nil)
        #expect(one.body == "the build is ready. Ship it.")

        let two = OutgoingDraft(kind: .mail, recipient: nil, text: "Build 12\n\nIt is ready.\n  Ship it.  ")
        #expect(two.subject == "Build 12")
        #expect(two.body == "It is ready.\nShip it.")

        let read = OutgoingDraft.request(in: "mail toni@example.com Build 12\nIt is ready.")
        #expect(read == OutgoingDraft(kind: .mail, recipient: "toni@example.com", text: "Build 12\nIt is ready."))
        #expect(read?.subject == "Build 12")
        #expect(OutgoingDraft(kind: .mail, recipient: nil, text: "only line\n\n").subject == nil, "an empty line is not a second one")
    }

    // MARK: The links

    @Test func aMailLinkCarriesTheAddressTheSubjectAndTheBody() {
        #expect(DraftLinks.mail(to: "toni@example.com", subject: nil, body: "the build is ready") == "mailto:toni@example.com?body=the%20build%20is%20ready")
        #expect(DraftLinks.mail(to: nil, subject: nil, body: "the build is ready") == "mailto:?body=the%20build%20is%20ready")
        #expect(DraftLinks.mail(to: "toni@example.com", subject: nil, body: "") == "mailto:toni@example.com")
        #expect(DraftLinks.mail(to: nil, subject: "", body: "") == "mailto:")
        #expect(DraftLinks.mail(to: "toni+floe@example.com", subject: "Build 12", body: "It is ready.\nShip it.")
            == "mailto:toni+floe@example.com?subject=Build%2012&body=It%20is%20ready.%0D%0AShip%20it.")
        #expect(DraftLinks.mail(to: "a b?c&d@example.com", subject: nil, body: "") == "mailto:a%20b%3Fc%26d@example.com", "an address cannot start the fields early")
    }

    @Test func everyCharacterOfTheBodySurvivesAMailLink() throws {
        let link = DraftLinks.mail(to: "toni@example.com", subject: "A&B? 50% + 1", body: Self.awkward)
        #expect(link.hasPrefix("mailto:toni@example.com?subject=A%26B%3F%2050%25%20%2B%201&body=Q%26A%3F%20yes%20%2B%20no%20%3D%20100%25%20%231%0D%0Asecond"))
        #expect(link.unicodeScalars.count(where: { !$0.isASCII }) == 0)
        #expect(link.filter { $0 == "?" } == "?")
        #expect(link.filter { $0 == "&" } == "&")
        #expect(!link.contains("+"), "a plus in the text is escaped, so nothing reads it as a space")
        let read = try fields(link)
        #expect(read["subject"] == "A&B? 50% + 1")
        #expect(read["body"] == Self.awkward.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(URL(string: link) != nil)

        let windows = DraftLinks.mail(to: nil, subject: nil, body: "a\r\nb\rc\nd")
        #expect(windows == "mailto:?body=a%0D%0Ab%0D%0Ac%0D%0Ad", "each kind of line break becomes one")
    }

    @Test func aMessageLinkCarriesTheNumberAndTheBody() throws {
        #expect(DraftLinks.message(to: "+15551234567", body: "running late") == "sms:+15551234567&body=running%20late")
        #expect(DraftLinks.message(to: "555-123-4567", body: "running late") == "sms:5551234567&body=running%20late")
        #expect(DraftLinks.message(to: nil, body: "running late") == "sms:&body=running%20late")
        #expect(DraftLinks.message(to: "+15551234567", body: "") == "sms:+15551234567")

        let link = DraftLinks.message(to: "+15551234567", body: Self.awkward)
        #expect(link.hasPrefix("sms:+15551234567&body=Q%26A%3F%20yes%20%2B%20no%20%3D%20100%25%20%231%0Asecond"))
        #expect(link.unicodeScalars.count(where: { !$0.isASCII }) == 0)
        #expect(link.filter { $0 == "&" } == "&")
        #expect(link.filter { $0 == "+" } == "+", "only the number keeps its plus")
        let body = try #require(link.components(separatedBy: "&body=").last)
        #expect(body.removingPercentEncoding == Self.awkward)
        #expect(URL(string: link) != nil)
    }

    @Test func aDraftBuildsItsOwnLink() {
        #expect(OutgoingDraft.request(in: "mail toni@example.com the build is ready")?.link?.absoluteString == "mailto:toni@example.com?body=the%20build%20is%20ready")
        #expect(OutgoingDraft.request(in: "mail the build is ready")?.link?.absoluteString == "mailto:?body=the%20build%20is%20ready")
        #expect(OutgoingDraft.request(in: "mail Build 12\nIt is ready")?.link?.absoluteString == "mailto:?subject=Build%2012&body=It%20is%20ready")
        #expect(OutgoingDraft.request(in: "message +15551234567 running late")?.link?.absoluteString == "sms:+15551234567&body=running%20late")
        #expect(OutgoingDraft.request(in: "message running late")?.link?.absoluteString == "sms:&body=running%20late")
        #expect(OutgoingDraft.request(in: "message first\nsecond")?.link?.absoluteString == "sms:&body=first%0Asecond", "a message has no subject")
    }

    // MARK: The row

    @Test func theRowSaysWhatIsWrittenAndToWhom() throws {
        let mail = try RootItem.outgoing(#require(OutgoingDraft.request(in: "mail toni@example.com the build is ready")))
        #expect(mail.title == "Mail: the build is ready")
        #expect(mail.rowLabel == "toni@example.com")
        #expect(mail.kind == "Mail")
        #expect(mail.id == "mail-draft")
        #expect(mail.isScopeResult)
        #expect(mail.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(mail), "text being typed is not something to favorite")

        let message = try RootItem.outgoing(#require(OutgoingDraft.request(in: "message running late")))
        #expect(message.title == "Message: running late")
        #expect(message.rowLabel == "No recipient")
        #expect(message.kind == "Message")
        #expect(message.id == "message-draft")

        let empty = try RootItem.outgoing(#require(OutgoingDraft.request(in: "mail toni@example.com")))
        #expect(empty.title == "Mail to toni@example.com")
        #expect(empty.rowLabel == "Mail")
        let bare = try RootItem.outgoing(#require(OutgoingDraft.request(in: "message +15551234567")))
        #expect(bare.title == "Message to +15551234567")
        #expect(bare.rowLabel == "Message")
        let lines = try RootItem.outgoing(#require(OutgoingDraft.request(in: "mail Build 12\nIt is ready")))
        #expect(lines.title == "Mail: Build 12")

        let pinned = OutgoingDraftSearchProvider().contribution(for: SearchContext(query: "mail the build is ready")).pinned
        #expect(pinned.map(\.item.title) == ["Mail: the build is ready"])
        #expect(pinned.map(\.item.rowLabel) == ["No recipient"])
    }

    @Test func somethingWhoseNameStartsWithTheTextKeepsTheLead() {
        var context = SearchContext(query: "mail me")
        #expect(RootSearch.results(for: context).first?.id == "mail-draft")
        let shortcut = AppleShortcut(name: "Mail Me the News", identifier: "6F1B2C3D-0000-4000-8000-000000000001")
        context.shortcuts = [shortcut]
        let found = RootSearch.results(for: context).map(\.id)
        #expect(found.first == shortcut.id)
        #expect(found.suffix(2) == ["mail-draft", "files-for:mail me"], "the draft is still offered, under the ranked rows")

        var longer = SearchContext(query: "mail me the build")
        longer.shortcuts = [shortcut]
        #expect(RootSearch.results(for: longer).first?.id == "mail-draft", "past the name, it is text for a draft")
        var app = SearchContext(query: "message board")
        app.apps = [AppEntry(name: "Message Board", url: URL(fileURLWithPath: "/Fake/Applications/Message Board.app"))]
        #expect(RootSearch.results(for: app).first?.id != "message-draft")
    }

    // MARK: Return

    @Test func returnOpensTheDraftAndLeavesNoReceipt() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let opened = Opened()
        let model = model(in: folder, opened: opened)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "mail toni@example.com the build is ready"
        let mail = try #require(model.results.first?.item)
        #expect(mail.title == "Mail: the build is ready")
        #expect(model.primaryActionTitle(for: mail) == "Open Draft")
        #expect(model.rootActions(for: mail).compactMap { $0?.title } == ["Open Draft"])
        model.activate(mail)
        #expect(opened.links == ["mailto:toni@example.com?body=the%20build%20is%20ready"])
        #expect(hidden == 1)
        #expect(model.query.isEmpty)

        model.query = "message +15551234567 running late"
        let message = try #require(model.results.first?.item)
        #expect(message.title == "Message: running late")
        model.activate(message)
        #expect(opened.links.last == "sms:+15551234567&body=running%20late")
        #expect(said.isEmpty, "the app shows the draft, so nothing is said")
        #expect(model.receipts.all.isEmpty, "nothing was sent or changed")

        model.query = "mail"
        #expect(model.results.first?.item.id != "mail-draft", "the word alone is an ordinary search")
    }
}
