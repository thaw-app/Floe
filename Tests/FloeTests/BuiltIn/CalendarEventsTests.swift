//
//  CalendarEventsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct CalendarEventsTests {
    private struct Refused: LocalizedError {
        var errorDescription: String? {
            "Calendar said no"
        }
    }

    /// What stands in for Apple Calendar: the identifiers it holds, and what was asked of it.
    private final class Stand {
        var isAllowed = true
        var asked = 0
        var created: [EventDraft] = []
        var held: Set<String> = []
        var deleted: [String] = []
        var fails = false
    }

    private static nonisolated let zone = TimeZone(identifier: "Europe/Madrid")!
    private static nonisolated var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// A time in October 2026. The 8th is a Thursday.
    private static nonisolated func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static nonisolated let now = time(8, 14)

    /// Reads a query at two in the afternoon of the 8th, with a detector that finds nothing unless one is given.
    private func request(_ query: String, detect: (String) -> ReminderDate.Found? = { _ in nil }) -> EventDraft? {
        EventDraft.request(in: query, now: Self.now, calendar: Self.calendar, detect: detect)
    }

    /// A detector that finds those words and says they mean that date.
    private func finding(_ words: String, as date: Date) -> (String) -> ReminderDate.Found? {
        { text in text.range(of: words).map { ReminderDate.Found(range: $0, date: date) } }
    }

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-events-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A model whose receipts are in the folder and whose events go to the stand-in, never to Apple Calendar.
    private func model(in folder: URL, stand: Stand) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-events-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.reminding = ReminderEnvironment(requestAccess: { false }, create: { _ in throw Refused() }, delete: { _ in throw Refused() }, lists: { [] })
        model.scheduling = EventEnvironment(
            requestAccess: {
                stand.asked += 1
                return stand.isAllowed
            },
            create: { draft in
                if stand.fails {
                    throw Refused()
                }
                stand.created.append(draft)
                let identifier = "event-\(stand.created.count)"
                stand.held.insert(identifier)
                return identifier
            },
            delete: { identifier in
                if stand.fails {
                    throw Refused()
                }
                stand.deleted.append(identifier)
                return stand.held.remove(identifier) != nil
            }
        )
        return model
    }

    // MARK: The sentence

    @Test func aSentenceWithATimeIsAnHourFromThen() {
        let draft = request("event lunch with Ana tomorrow at 1pm", detect: finding("tomorrow at 1pm", as: Self.time(9, 13)))
        #expect(draft == EventDraft(title: "lunch with Ana", start: Self.time(9, 13), isAllDay: false))
        #expect(draft?.end == Self.time(9, 14))
        #expect(request("Event  standup at 3:30") == EventDraft(title: "standup", start: Self.time(8, 15, 30), isAllDay: false))
        #expect(request("event call in 2 hours")?.start == Self.time(8, 16))
        #expect(request("event film tonight") == EventDraft(title: "film", start: Self.time(8, 20), isAllDay: false))
    }

    @Test func aDayWithNoTimeFillsTheDay() {
        let draft = request("event conference on oct 15", detect: finding("oct 15", as: Self.time(15, 12)))
        #expect(draft == EventDraft(title: "conference", start: Self.time(15, 0), isAllDay: true))
        #expect(draft?.end == Self.time(15, 0), "an all-day event ends on the day it starts")
        #expect(request("event rent on the 22nd") == EventDraft(title: "rent", start: Self.time(22, 0), isAllDay: true), "the rule's nine in the morning is not a time the user typed")
    }

    @Test func aSentenceWithNoDateIsADraftWithNoStart() {
        #expect(request("event lunch with Ana") == EventDraft(title: "lunch with Ana", start: nil, isAllDay: false))
        #expect(request("event lunch with Ana")?.end == nil)
    }

    @Test(arguments: ["event", "event ", "events today", "eventful day", "lunch event tomorrow"])
    func anythingElseIsAnOrdinarySearch(query: String) {
        #expect(EventDraft.request(in: query) == nil)
        #expect(EventSearchProvider().contribution(for: SearchContext(query: query)).pinned.isEmpty)
    }

    @Test(arguments: [
        ("tomorrow at 5pm", true), ("Thursday noon", true), ("next friday 9:30", true), ("in 2 hours", true), ("in 20 minutes", true),
        ("tonight", true), ("at 3", true), ("at 17:45", true), ("tomorrow morning", true), ("5 PM", true),
        ("tomorrow", false), ("oct 15", false), ("on the 1st", false), ("in 3 weeks", false), ("next friday", false), ("10/15/2026", false),
    ])
    func theWordsOfADateSayWhetherItHasATime(words: String, hasTime: Bool) {
        #expect(ReminderDate.saysATime(words) == hasTime)
    }

    /// The detector reads the clock and the Mac's time zone, so these say what holds whenever they run.
    @Test func theSystemsDetectorReadsTheUsualPhrases() throws {
        let calendar = Calendar.current
        let noon = try #require(EventDraft.request(in: "event lunch with Ana Thursday noon"))
        #expect(noon.title.hasPrefix("lunch"))
        #expect(!noon.isAllDay)
        let start = try #require(noon.start)
        #expect(start > Date())
        #expect(calendar.dateComponents([.weekday, .hour, .minute], from: start) == DateComponents(hour: 12, minute: 0, weekday: 5))
        #expect(noon.end == start.addingTimeInterval(3600))

        let day = try #require(EventDraft.request(in: "event conference on oct 15"))
        #expect(day.title == "conference")
        #expect(day.isAllDay)
        #expect(try calendar.dateComponents([.month, .day, .hour, .minute], from: #require(day.start)) == DateComponents(month: 10, day: 15, hour: 0, minute: 0))
    }

    // MARK: The row

    @Test func theRowSaysWhatIsAddedAndWhen() {
        let draft = EventDraft(title: "lunch with Ana", start: Self.time(9, 13), isAllDay: false)
        let british = Locale(identifier: "en_GB")
        #expect(draft.label(locale: british, timeZone: Self.zone) == "Fri 9 Oct at 13:00")
        #expect(draft.label(locale: british, timeZone: Self.zone) == ReminderDraft(title: "x", due: Self.time(9, 13)).label(locale: british, timeZone: Self.zone), "the form the reminder row uses")
        #expect(EventDraft(title: "conference", start: Self.time(15, 0), isAllDay: true).label(locale: british, timeZone: Self.zone) == "Thu 15 Oct, all day")
        #expect(EventDraft(title: "lunch", start: nil).label() == "Add a day or time")

        let row = RootItem.eventDraft(draft)
        #expect(row.title == "Event: lunch with Ana")
        #expect(row.rowLabel == draft.label())
        #expect(row.kind == "Event")
        #expect(row.id == "event-draft")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(row), "a sentence being typed is not something to favorite")

        let pinned = EventSearchProvider().contribution(for: SearchContext(query: "event lunch with Ana")).pinned
        #expect(pinned.map(\.item.title) == ["Event: lunch with Ana"])
        #expect(pinned.map(\.item.rowLabel) == ["Add a day or time"])
    }

    @Test(arguments: ["event lunch with Ana in 2 hours", "event lunch with Ana", "event lunch with Ana Thursday noon"])
    func theSentenceDoesNotAskForTheAgenda(query: String) {
        #expect(!CalendarAgenda.isTrigger(query), "the agenda is what asks macOS for the calendar while typing")
    }

    // MARK: Return

    @Test func returnAddsTheEventSaysSoAndLeavesAReceipt() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "event lunch with Ana in 2 hours"
        let row = try #require(model.results.first?.item)
        #expect(row.title == "Event: lunch with Ana")
        #expect(model.primaryActionTitle(for: row) == "Add Event")
        #expect(model.rootActions(for: row).compactMap { $0?.title }.first == "Add Event")

        model.activate(row)
        for _ in 0 ..< 100 where said.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(hidden == 1)
        #expect(stand.created.map(\.title) == ["lunch with Ana"])
        let created = try #require(stand.created.first)
        #expect(!created.isAllDay)
        #expect(try abs(#require(created.start).timeIntervalSinceNow - 7200) < 60)
        #expect(said == ["Added the event lunch with Ana"])

        let receipt = try #require(model.receipts.all.first)
        #expect(receipt.kind == .event)
        #expect(receipt.subject == "lunch with Ana")
        #expect(receipt.identifier == "event-1")
        #expect(receipt.detail == created.label())
        #expect(receipt.title == "Added the event lunch with Ana")
    }

    @Test func aSentenceWithNoDateAddsNothingAndSaysWhatIsMissing() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "event lunch with Ana"
        let row = try #require(model.results.first?.item)
        #expect(row.rowLabel == "Add a day or time")
        model.activate(row)
        await model.addEvent(EventDraft(title: "lunch with Ana", start: nil)).value
        #expect(said == Array(repeating: "Add a day or time to the event, such as Thursday noon", count: 2))
        #expect(hidden == 0, "the panel stays so the day can be typed")
        #expect(model.query == "event lunch with Ana")
        #expect(stand.asked == 0, "macOS is not asked for the calendar over an event that cannot be added")
        #expect(stand.created.isEmpty)
        #expect(model.receipts.all.isEmpty)
    }

    @Test func refusedAccessSaysSoAndAddsNothing() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.isAllowed = false
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        let draft = EventDraft(title: "lunch", start: Self.time(9, 13))
        await model.addEvent(draft).value
        #expect(said == ["Floe may not use Calendar. Allow full access in System Settings > Privacy & Security > Calendars."])
        #expect(stand.created.isEmpty)
        #expect(model.receipts.all.isEmpty)

        stand.isAllowed = true
        stand.fails = true
        await model.addEvent(draft).value
        #expect(said.last == "Calendar said no", "what Calendar answered is what is said")
        #expect(model.receipts.all.isEmpty)

        stand.fails = false
        model.settings.keepsReceipts = false
        await model.addEvent(draft).value
        #expect(stand.created == [draft])
        #expect(model.receipts.all.isEmpty, "receipts switched off: the event is added and no record kept")
    }

    // MARK: The receipt

    @Test func returnOnTheReceiptDeletesTheEvent() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var shown: [String] = []
        model.shell.showOutput = { title, _ in shown.append(title) }
        await model.addEvent(EventDraft(title: "lunch", start: Self.time(9, 13))).value
        let receipt = try #require(model.receipts.all.first)
        let row = RootItem.receipt(receipt)
        #expect(receipt.canUndo)
        #expect(receipt.label().hasSuffix(" · can be deleted"))
        #expect(model.primaryActionTitle(for: row) == "Delete Event")
        #expect(model.rootActions(for: row).map { $0?.title ?? "-" } == ["Delete Event", "Show Details", "-", "Copy"])

        stand.fails = true
        model.activate(row)
        #expect(said.last == "Calendar said no")
        #expect(model.receipts.all.first?.canUndo == true, "a delete that failed can be tried again")

        stand.fails = false
        model.activate(row)
        #expect(stand.deleted == ["event-1"])
        #expect(stand.held.isEmpty)
        #expect(said.last == "Deleted the event lunch")
        let after = try #require(model.receipts.all.first)
        #expect(!after.canUndo, "once is enough")
        #expect(after.label().hasSuffix(" · deleted"))
        #expect(after.text.contains("\nDeleted "))
        #expect(model.primaryActionTitle(for: .receipt(after)) == "Show Details")
        model.activate(.receipt(after))
        #expect(stand.deleted.count == 1)
        #expect(shown == ["Added the event lunch"])
    }

    @Test func anEventThatIsAlreadyGoneIsSaidToBeAndTheReceiptIsSettled() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.addEvent(EventDraft(title: "lunch", start: Self.time(9, 13))).value
        let receipt = try #require(model.receipts.all.first)
        stand.held.removeAll()

        model.undo(receipt)
        #expect(said.last == "The event lunch was already deleted")
        #expect(model.receipts.all.first?.canUndo == false)
    }

    @Test func aReceiptFileFromBeforeEventsStillReads() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Receipts.json")
        let old = #"[{"id":"6F1B2C3D-0000-4000-8000-000000000002","date":0,"kind":"reminder","subject":"call mom","detail":"No date","reminder":"abc"},"#
            + #"{"id":"6F1B2C3D-0000-4000-8000-000000000001","date":0,"kind":"trash","subject":"a.txt","detail":"~/a.txt","original":"/a","trashed":"/b"}]"#
        try Data(old.utf8).write(to: file)
        let store = ReceiptStore(file: file)
        #expect(store.all.map(\.identifier) == ["abc", nil], "the identifier keeps the name it was written under")
        #expect(store.all.map(\.canUndo) == [true, true])
        store.add(Receipt(date: Date(), kind: .event, subject: "lunch", detail: "", identifier: "xyz"))
        let again = ReceiptStore(file: file).all
        #expect(again.map(\.kind) == [.event, .reminder, .trash])
        #expect(again.map(\.identifier) == ["xyz", "abc", nil])
        #expect(try String(contentsOf: file, encoding: .utf8).contains(#""reminder":"xyz""#))
    }
}
