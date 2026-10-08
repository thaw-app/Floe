//
//  RemindersTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct RemindersTests {
    private struct Refused: LocalizedError {
        var errorDescription: String? {
            "Reminders said no"
        }
    }

    /// What stands in for Apple Reminders: the identifiers it holds, and what was asked of it.
    private final class Stand {
        var isAllowed = true
        var created: [ReminderDraft] = []
        var held: Set<String> = []
        var deleted: [String] = []
        var fails = false
        var lists: [String] = []
        var listsRead = 0
    }

    private static nonisolated let zone = TimeZone(identifier: "Europe/Madrid")!
    private static nonisolated var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// A time in October 2026 unless said otherwise. The 8th is a Thursday.
    private static nonisolated func time(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static nonisolated let now = time(8, 14)

    /// Reads a sentence at two in the afternoon of the 8th, with a detector that finds nothing unless one is given.
    private func read(_ text: String, now: Date = now, detect: (String) -> ReminderDate.Found? = { _ in nil }) -> ReminderDraft {
        ReminderDate.read(text, now: now, calendar: Self.calendar, detect: detect)
    }

    /// A detector that finds those words and says they mean that date.
    private func finding(_ words: String, as date: Date) -> (String) -> ReminderDate.Found? {
        { text in text.range(of: words).map { ReminderDate.Found(range: $0, date: date) } }
    }

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-reminders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A model whose receipts are in the folder and whose reminders go to the stand-in, never to Apple Reminders.
    private func model(in folder: URL, stand: Stand) -> LauncherModel {
        let defaults = UserDefaults(suiteName: "floe-reminders-\(UUID().uuidString)")!
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        model.reminding = ReminderEnvironment(
            requestAccess: { stand.isAllowed },
            create: { draft in
                if stand.fails {
                    throw Refused()
                }
                stand.created.append(draft)
                let identifier = "reminder-\(stand.created.count)"
                stand.held.insert(identifier)
                return identifier
            },
            delete: { identifier in
                if stand.fails {
                    throw Refused()
                }
                stand.deleted.append(identifier)
                return stand.held.remove(identifier) != nil
            },
            lists: {
                stand.listsRead += 1
                return stand.lists
            }
        )
        return model
    }

    // MARK: The keyword

    @Test(arguments: [
        ("remind call mom", "call mom"),
        ("Remind  me to call mom", "call mom"),
        ("remind me call mom", "call mom"),
        ("remind meet Ana", "meet Ana"),
    ])
    func theKeywordAndASentence(query: String, title: String) {
        let draft = ReminderDraft.request(in: query, now: Self.now, calendar: Self.calendar) { _ in nil }
        #expect(draft?.title == title)
        #expect(draft?.due == nil)
    }

    @Test(arguments: ["remind", "remind ", "reminder call mom", "reminds me", "call mom remind"])
    func anythingElseIsAnOrdinarySearch(query: String) {
        #expect(ReminderDraft.request(in: query) == nil)
        #expect(ReminderSearchProvider().contribution(for: SearchContext(query: query)).pinned.isEmpty)
    }

    // MARK: The list

    @Test(arguments: [
        ("remind call mom in Work", "call mom", "Work"),
        ("remind call mom in work", "call mom", "Work"),
        ("remind call mom list WORK", "call mom", "Work"),
        ("remind call mom in list Work", "call mom", "Work"),
        ("remind me to buy paint in home projects", "buy paint", "Home Projects"),
        ("remind buy paint in Home", "buy paint", "Home"),
        ("remind call mom in Garden", "call mom in Garden", nil),
        ("remind call mom in Workshop", "call mom in Workshop", nil),
        ("remind fix the framework", "fix the framework", nil),
        ("remind work in Work on Friday", "work in Work on Friday", nil),
        ("remind in Work", "in Work", nil),
        ("remind list Work", "list Work", nil),
    ])
    func aSentenceThatEndsByNamingAListGoesThere(query: String, title: String, list: String?) {
        let draft = ReminderDraft.request(in: query, now: Self.now, calendar: Self.calendar, lists: ["Home", "Work", "Home Projects", ""]) { _ in nil }
        #expect(draft == ReminderDraft(title: title, due: nil, list: list))
    }

    @Test func aDateThatStartsWithInIsStillADate() throws {
        let lists = ["Work", "2 hours", "3 weeks"]
        let none: (String) -> ReminderDate.Found? = { _ in nil }
        #expect(ReminderDraft.request(in: "remind call in 2 hours", now: Self.now, calendar: Self.calendar, lists: lists, detect: none) == ReminderDraft(title: "call", due: Self.time(8, 16)))
        let both = ReminderDraft.request(in: "remind call mom in 2 hours in Work", now: Self.now, calendar: Self.calendar, lists: lists, detect: none)
        #expect(both == ReminderDraft(title: "call mom", due: Self.time(8, 16), list: "Work"))
        let tomorrow = ReminderDraft.request(in: "remind call mom tomorrow at 5pm list work", now: Self.now, calendar: Self.calendar, lists: lists, detect: finding("tomorrow at 5pm", as: Self.time(9, 17)))
        #expect(tomorrow == ReminderDraft(title: "call mom", due: Self.time(9, 17), list: "Work"))

        let weeks = try #require(ReminderDraft.request(in: "remind renew passport in 3 weeks", lists: lists))
        #expect(weeks.title == "renew passport")
        #expect(weeks.list == nil)
        #expect(weeks.due != nil, "the system's detector reads it, so it is not the list of that name")
        #expect(ReminderDraft.request(in: "remind call mom in Work")?.list == nil, "with no lists known the words stay in the title")
    }

    @Test func theListsAreReadOnlyWhileAReminderIsTypedAndTheRowShowsTheOneNamed() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.lists = ["Home", "Work"]
        let model = model(in: folder, stand: stand)
        model.query = "rem"
        model.query = "safari in Work"
        #expect(stand.listsRead == 0)

        model.query = "remind call mom in work"
        #expect(stand.listsRead > 0)
        let row = try #require(model.results.first?.item)
        #expect(row.title == "Remind: call mom")
        #expect(row.rowLabel == "No date · Work")
        guard case let .reminderDraft(draft) = row else { return }
        await model.addReminder(draft).value
        #expect(stand.created == [ReminderDraft(title: "call mom", due: nil, list: "Work")])
        #expect(model.receipts.all.first?.detail == "No date · Work")

        model.query = "remind call mom in Garden"
        #expect(model.results.first?.item.title == "Remind: call mom in Garden")
        #expect(model.results.first?.item.rowLabel == "No date")
    }

    // MARK: The rules

    @Test(arguments: [
        ("call in 2 hours", "call", time(8, 16)),
        ("call in 1 hour", "call", time(8, 15)),
        ("stretch in an hour", "stretch", time(8, 15)),
        ("tea in 20 minutes", "tea", time(8, 14, 20)),
        ("tea in 1 minute", "tea", time(8, 14, 1)),
        ("In 90 minutes leave for the airport", "leave for the airport", time(8, 15, 30)),
        ("sleep in 11 hours", "sleep", time(9, 1)),
    ])
    func inSomeMinutesOrHoursCountsFromNow(text: String, title: String, due: Date) {
        #expect(read(text) == ReminderDraft(title: title, due: due))
    }

    @Test(arguments: [
        ("call at 3", time(8, 15)),
        ("call at 3pm", time(8, 15)),
        ("call at 3 PM", time(8, 15)),
        ("call at 3:30", time(8, 15, 30)),
        ("call at 9", time(8, 21)),
        ("call at 9am", time(9, 9)),
        ("call at 1", time(9, 1)),
        ("call at 2", time(9, 2)),
        ("call at 12am", time(9, 0)),
        ("call at 12pm", time(9, 12)),
        ("call at 17:45", time(8, 17, 45)),
        ("call at 13:00", time(9, 13)),
        ("call at 0:15", time(9, 0, 15)),
    ])
    func atAnHourIsTheNextTimeTheClockSaysSo(text: String, due: Date) {
        #expect(read(text) == ReminderDraft(title: "call", due: due))
    }

    @Test func tonightIsEightInTheEveningOrTomorrowsOnceItHasPassed() {
        #expect(read("movie tonight") == ReminderDraft(title: "movie", due: Self.time(8, 20)))
        #expect(read("Tonight take the bins out") == ReminderDraft(title: "take the bins out", due: Self.time(8, 20)))
        #expect(read("movie tonight", now: Self.time(8, 21)) == ReminderDraft(title: "movie", due: Self.time(9, 20)))
    }

    @Test func onTheNthIsNineInTheMorningOfTheNextSuchDay() {
        #expect(read("rent on the 1st") == ReminderDraft(title: "rent", due: Self.time(1, 9, month: 11)))
        #expect(read("pay on the 22nd for the hall") == ReminderDraft(title: "pay for the hall", due: Self.time(22, 9)))
        #expect(read("report on the 8th") == ReminderDraft(title: "report", due: Self.time(8, 9, month: 11)), "nine has passed today")
        #expect(read("report on the 8th", now: Self.time(8, 7)).due == Self.time(8, 9))
        #expect(read("close the books on the 31st", now: Self.time(5, 12, month: 11)).due == Self.time(31, 9, month: 12), "November has no 31st")
        #expect(read("rent on the 1st", now: Self.time(20, 12, month: 12)).due == Self.time(1, 9, month: 1, year: 2027))
    }

    @Test(arguments: ["buy milk", "meet at 25", "call at 3:75", "party on the 40th", "room at 221b", "in 2 days maybe", "at3", "look at the 3 options"])
    func textWithNoDateIsAReminderWithNone(text: String) {
        #expect(read(text) == ReminderDraft(title: text, due: nil))
    }

    // MARK: The detector and the rules together

    @Test func whatTheDetectorFindsAheadOfNowIsTheDateAndLeavesTheTitle() {
        let tomorrow = Self.time(9, 17)
        #expect(read("call mom tomorrow at 5pm", detect: finding("tomorrow at 5pm", as: tomorrow)) == ReminderDraft(title: "call mom", due: tomorrow))
        #expect(read("dentist on oct 15 with x-rays", detect: finding("oct 15", as: Self.time(15, 12))).title == "dentist with x-rays")
        #expect(read("be home by tomorrow", detect: finding("tomorrow", as: Self.time(9, 12))).title == "be home")
        let whole = read("lunch Thursday noon", detect: finding("lunch Thursday noon", as: Self.time(15, 12)))
        #expect(whole == ReminderDraft(title: "lunch Thursday noon", due: Self.time(15, 12)), "a date that took every word leaves the sentence as the title")
    }

    @Test func aTimeTheDetectorPutEarlierTodayIsReadByTheRules() {
        let evening = Self.time(8, 18)
        #expect(read("call at 3pm", now: evening, detect: finding("3pm", as: Self.time(8, 15))) == ReminderDraft(title: "call", due: Self.time(9, 15)))
        #expect(read("movie tonight", now: Self.time(8, 21), detect: finding("tonight", as: Self.time(8, 20))).due == Self.time(9, 20))
        #expect(read("call today", now: evening, detect: finding("today", as: Self.time(8, 12))).due == Self.time(8, 12), "no rule reads it, and today stays today")
    }

    @Test func aDayOfTheYearThatHasPassedIsNextYears() {
        let draft = read("pay tax on sep 1", detect: finding("sep 1", as: Self.time(1, 12, month: 9)))
        #expect(draft == ReminderDraft(title: "pay tax", due: Self.time(1, 12, month: 9, year: 2027)))
    }

    /// The detector reads the clock and the Mac's time zone, so these say what holds whenever they run.
    @Test func theSystemsDetectorReadsTheUsualPhrases() throws {
        let now = Date()
        let calendar = Calendar.current
        let parts: (ReminderDraft) throws -> DateComponents = { try calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: #require($0.due)) }

        let tomorrow = ReminderDate.read("call mom tomorrow at 5pm", now: now, calendar: calendar)
        #expect(tomorrow.title == "call mom")
        #expect(try calendar.isDateInTomorrow(#require(tomorrow.due)))
        #expect(try parts(tomorrow).hour == 17)

        let friday = ReminderDate.read("standup next friday 9:30", now: now, calendar: calendar)
        #expect(friday.title == "standup")
        #expect(try [parts(friday).weekday, parts(friday).hour, parts(friday).minute] == [6, 9, 30])

        let october = ReminderDate.read("dentist on oct 15", now: now, calendar: calendar)
        #expect(october.title == "dentist")
        #expect(try [parts(october).month, parts(october).day] == [10, 15])

        let weeks = ReminderDate.read("renew passport in 3 weeks", now: now, calendar: calendar)
        #expect(weeks.title == "renew passport")
        let inThreeWeeks = try #require(calendar.date(byAdding: .day, value: 21, to: now))
        #expect(try calendar.isDate(#require(weeks.due), inSameDayAs: inThreeWeeks))

        let noon = ReminderDate.read("lunch Thursday noon", now: now, calendar: calendar)
        #expect(noon.title.hasPrefix("lunch"))
        #expect(try [parts(noon).weekday, parts(noon).hour] == [5, 12])
    }

    @Test(arguments: [
        "call mom tomorrow at 5pm", "standup next friday 9:30", "dentist on oct 15", "renew passport in 3 weeks", "lunch Thursday noon",
        "call in 2 hours", "tea in 20 minutes", "call at 3", "call at 3pm", "call at 3:30", "movie tonight", "rent on the 1st",
    ])
    func everyPhraseIsDueAfterNowWithTheSystemsDetector(text: String) throws {
        let now = Date()
        let due = try #require(ReminderDate.read(text, now: now, calendar: .current).due)
        #expect(due > now)
    }

    // MARK: The row

    @Test func theRowSaysWhatIsRemindedAndWhen() {
        let draft = ReminderDraft(title: "call mom", due: Self.time(9, 17))
        #expect(draft.label(locale: Locale(identifier: "en_GB"), timeZone: Self.zone) == "Fri 9 Oct at 17:00")
        let american = draft.label(locale: Locale(identifier: "en_US"), timeZone: Self.zone)
        #expect(american.hasPrefix("Fri, Oct 9 at 5:00") && american.hasSuffix("PM"), "the user's own way of writing a date")
        #expect(ReminderDraft(title: "buy milk", due: nil).label() == "No date")
        #expect(ReminderDraft(title: "call mom", due: Self.time(9, 17), list: "Work").label(locale: Locale(identifier: "en_GB"), timeZone: Self.zone) == "Fri 9 Oct at 17:00 · Work")
        #expect(ReminderDraft(title: "buy milk", due: nil, list: "Home").label() == "No date · Home")

        let row = RootItem.reminderDraft(draft)
        #expect(row.title == "Remind: call mom")
        #expect(row.rowLabel == draft.label())
        #expect(row.kind == "Reminder")
        #expect(row.isScopeResult)
        #expect(row.settingsKey == nil)
        #expect(!LauncherModel.keepsItsPlace(row), "a sentence being typed is not something to favorite")

        let pinned = ReminderSearchProvider().contribution(for: SearchContext(query: "remind buy milk")).pinned
        #expect(pinned.map(\.item.title) == ["Remind: buy milk"])
        #expect(pinned.map(\.item.rowLabel) == ["No date"])
    }

    // MARK: Return

    @Test func returnAddsTheReminderSaysSoAndLeavesAReceipt() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var hidden = 0
        model.hidePanel = { hidden += 1 }

        model.query = "remind call mom in 2 hours"
        let row = try #require(model.results.first?.item)
        #expect(row.title == "Remind: call mom")
        #expect(row.rowLabel != "No date")
        #expect(model.primaryActionTitle(for: row) == "Add Reminder")
        #expect(model.rootActions(for: row).compactMap { $0?.title }.first == "Add Reminder")

        model.activate(row)
        for _ in 0 ..< 100 where said.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(hidden == 1)
        #expect(stand.created.map(\.title) == ["call mom"])
        let due = try #require(stand.created.first?.due)
        #expect(abs(due.timeIntervalSinceNow - 7200) < 60)
        #expect(said == ["Added the reminder call mom"])

        let receipt = try #require(model.receipts.all.first)
        #expect(receipt.kind == .reminder)
        #expect(receipt.subject == "call mom")
        #expect(receipt.identifier == "reminder-1")
        #expect(receipt.detail == stand.created.first?.label())
        #expect(receipt.title == "Added the reminder call mom")
    }

    @Test func aSentenceWithNoDateAddsAReminderWithNone() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        model.query = "remind buy milk"
        let row = try #require(model.results.first?.item)
        #expect(row.rowLabel == "No date")
        await model.addReminder(ReminderDraft(title: "buy milk", due: nil)).value
        #expect(stand.created == [ReminderDraft(title: "buy milk", due: nil)])
        #expect(model.receipts.all.first?.detail == "No date")

        model.settings.keepsReceipts = false
        await model.addReminder(ReminderDraft(title: "buy bread", due: nil)).value
        #expect(stand.created.count == 2)
        #expect(model.receipts.all.count == 1, "receipts switched off: the reminder is added and no record kept")
    }

    @Test func refusedAccessSaysSoAndAddsNothing() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        stand.isAllowed = false
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.addReminder(ReminderDraft(title: "call mom", due: nil)).value
        #expect(said == ["Floe may not use Reminders. Allow it in System Settings > Privacy & Security > Reminders."])
        #expect(stand.created.isEmpty)
        #expect(model.receipts.all.isEmpty)

        stand.isAllowed = true
        stand.fails = true
        await model.addReminder(ReminderDraft(title: "call mom", due: nil)).value
        #expect(said.last == "Reminders said no", "what Reminders answered is what is said")
        #expect(model.receipts.all.isEmpty)
    }

    // MARK: The receipt

    @Test func returnOnTheReceiptDeletesTheReminder() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        var shown: [String] = []
        model.shell.showOutput = { title, _ in shown.append(title) }
        await model.addReminder(ReminderDraft(title: "call mom", due: Self.time(9, 17))).value
        let receipt = try #require(model.receipts.all.first)
        let row = RootItem.receipt(receipt)
        #expect(receipt.canUndo)
        #expect(receipt.label().hasSuffix(" · can be deleted"))
        #expect(model.primaryActionTitle(for: row) == "Delete Reminder")
        #expect(model.rootActions(for: row).map { $0?.title ?? "-" } == ["Delete Reminder", "Show Details", "-", "Copy"])

        stand.fails = true
        model.activate(row)
        #expect(said.last == "Reminders said no")
        #expect(model.receipts.all.first?.canUndo == true, "a delete that failed can be tried again")

        stand.fails = false
        model.activate(row)
        #expect(stand.deleted == ["reminder-1"])
        #expect(stand.held.isEmpty)
        #expect(said.last == "Deleted the reminder call mom")
        let after = try #require(model.receipts.all.first)
        #expect(!after.canUndo, "once is enough")
        #expect(after.label().hasSuffix(" · deleted"))
        #expect(after.text.contains("\nDeleted "))
        #expect(model.primaryActionTitle(for: .receipt(after)) == "Show Details")
        model.activate(.receipt(after))
        #expect(stand.deleted.count == 1)
        #expect(shown == ["Added the reminder call mom"])
    }

    @Test func aReminderThatIsAlreadyGoneIsSaidToBeAndTheReceiptIsSettled() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stand = Stand()
        let model = model(in: folder, stand: stand)
        var said: [String] = []
        model.showHUD = { said.append($0) }
        await model.addReminder(ReminderDraft(title: "call mom", due: nil)).value
        let receipt = try #require(model.receipts.all.first)
        stand.held.removeAll()

        model.undo(receipt)
        #expect(said.last == "The reminder call mom was already deleted")
        #expect(model.receipts.all.first?.canUndo == false)
    }

    @Test func undoingGoesThroughTheClosureItIsGiven() {
        let receipt = Receipt(date: Date(), kind: .reminder, subject: "call mom", detail: "No date", identifier: "abc")
        var asked: [String] = []
        let outcome = ReceiptUndo.undo(receipt) { identifier in
            asked.append(identifier)
            return true
        }
        #expect(outcome == .deleted)
        #expect(asked == ["abc"])
        #expect(ReceiptUndo.undo(receipt) { _ in false } == .alreadyDeleted)
        #expect(ReceiptUndo.undo(receipt) { _ in throw Refused() } == .failed("Reminders said no"))
        #expect(ReceiptUndo.undo(receipt) == .notUndoable, "with nothing to delete it through, Reminders is not touched")
        var undone = receipt
        undone.undone = Date()
        #expect(ReceiptUndo.undo(undone) { _ in true } == .notUndoable)
    }

    @Test func aReceiptFileFromBeforeRemindersStillReads() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Receipts.json")
        let old = #"[{"id":"6F1B2C3D-0000-4000-8000-000000000001","date":0,"kind":"trash","subject":"a.txt","detail":"~/a.txt","original":"/a","trashed":"/b"}]"#
        try Data(old.utf8).write(to: file)
        let store = ReceiptStore(file: file)
        #expect(store.all.map(\.subject) == ["a.txt"])
        #expect(store.all.first?.identifier == nil)
        #expect(store.all.first?.canUndo == true)
        store.add(Receipt(date: Date(), kind: .reminder, subject: "call mom", detail: "", identifier: "abc"))
        #expect(ReceiptStore(file: file).all.map(\.kind) == [.reminder, .trash])
    }
}
