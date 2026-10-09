//
//  MomentPatternTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor
struct MomentPatternTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    /// A time of day on a date where the user is, in Los Angeles.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    private func scratchVault(_ settings: String?) throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("floe-moment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        if let settings {
            try Data(settings.utf8).write(to: vault.appendingPathComponent(".obsidian/daily-notes.json"))
        }
        return vault
    }

    // MARK: The tokens

    /// Thursday 8 October 2026, in the forty-first week, and Monday 5 January 2026, in the second.
    @Test(arguments: [
        ("YYYY", "2026", "2026"), ("YY", "26", "26"), ("MMMM", "October", "January"), ("MMM", "Oct", "Jan"), ("MM", "10", "01"), ("M", "10", "1"),
        ("DD", "08", "05"), ("D", "8", "5"), ("Do", "8th", "5th"), ("dddd", "Thursday", "Monday"), ("ddd", "Thu", "Mon"), ("WW", "41", "02"), ("W", "41", "2"),
    ])
    func eachTokenIsWrittenAsMomentWritesIt(token: String, october: String, january: String) {
        #expect(MomentPattern.text(token, for: date(2026, 10, 8), in: pacific) == october)
        #expect(MomentPattern.text(token, for: date(2026, 1, 5), in: pacific) == january)
    }

    @Test(arguments: [(1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"), (12, "12th"), (13, "13th"), (21, "21st"), (22, "22nd"), (23, "23rd"), (30, "30th"), (31, "31st")])
    func theDayOfTheMonthAsAnOrdinal(day: Int, written: String) {
        #expect(MomentPattern.ordinal(day) == written)
        #expect(MomentPattern.text("Do", for: date(2026, 10, day), in: pacific) == written)
    }

    @Test(arguments: [
        ("YYYY-MM-DD", "2026-10-08"), ("DD.MM.YY", "08.10.26"), ("dddd, MMMM Do YYYY", "Thursday, October 8th 2026"), ("YYYY_MM_DD ddd", "2026_10_08 Thu"),
        ("MMM D, YYYY", "Oct 8, 2026"), ("YYYYMMDD", "20261008"),
    ])
    func tokensAndWhatStandsBetweenThem(pattern: String, written: String) {
        #expect(MomentPattern.text(pattern, for: date(2026, 10, 8), in: pacific) == written)
    }

    @Test func theWeekIsTheISOWeekAndTheDayIsTheOneInTheZoneAsked() throws {
        #expect(MomentPattern.text("W", for: date(2027, 1, 1), in: pacific) == "53", "the first of January 2027 is a Friday, still in the last week of 2026")
        #expect(MomentPattern.text("WW", for: date(2026, 12, 28), in: pacific) == "53")
        #expect(MomentPattern.text("W", for: date(2027, 1, 4), in: pacific) == "1")
        let utc = try #require(TimeZone(identifier: "UTC"))
        let evening = date(2026, 10, 8, hour: 17)
        #expect(MomentPattern.text("YYYY-MM-DD ddd", for: evening, in: pacific) == "2026-10-08 Thu")
        #expect(MomentPattern.text("YYYY-MM-DD ddd", for: evening, in: utc) == "2026-10-09 Fri", "already Friday in UTC")
    }

    // MARK: Brackets and subfolders

    @Test(arguments: [
        ("[Daily] YYYY-MM-DD", "Daily 2026-10-08"), ("YYYY-MM-DD[ (daily)]", "2026-10-08 (daily)"), ("[Day] D [of] MMMM", "Day 8 of October"),
        ("[YYYY] YYYY", "YYYY 2026"), ("YYYY-[W]WW", "2026-W41"), ("[]YYYY", "2026"),
    ])
    func textInBracketsIsKeptAsItIs(pattern: String, written: String) {
        #expect(MomentPattern.text(pattern, for: date(2026, 10, 8), in: pacific) == written)
    }

    @Test(arguments: [("YYYY/MM/YYYY-MM-DD", "2026/10/2026-10-08"), ("YYYY/MMMM/DD dddd", "2026/October/08 Thursday"), ("[Journal]/YYYY/[Week] WW/ddd", "Journal/2026/Week 41/Thu")])
    func aSlashStartsASubfolder(pattern: String, written: String) {
        #expect(MomentPattern.text(pattern, for: date(2026, 10, 8), in: pacific) == written)
    }

    // MARK: What Floe does not read

    @Test(arguments: [
        "YYYY-MM-DD HH", "YYYY-MM-DD hh.mm", "gggg-[W]ww", "GGGG-[W]WW", "YYYY-DDD", "YYYY-DDDD", "dd D", "d", "Mo MMMM", "Q YYYY", "YYYYY", "YYY", "MMMMM",
        "YYYY-MM-DD A", "X", "YYYY-MM-DD[unclosed", "YYYY:MM:DD", "YYYY\\MM", "DDo", "wo", "E",
    ])
    func aPatternWithATokenOutsideTheSetIsNotGuessedAt(pattern: String) {
        #expect(MomentPattern.text(pattern, for: date(2026, 10, 8), in: pacific) == nil)
    }

    @Test(arguments: ["/YYYY-MM-DD", "YYYY-MM-DD/", "YYYY//MM", "../YYYY-MM-DD", "YYYY/[..]/DD", "[.]/YYYY", "YYYY/ /DD", ""])
    func aPatternThatLeadsOutOfTheFolderOrNamesNothingIsRefused(pattern: String) {
        #expect(MomentPattern.text(pattern, for: date(2026, 10, 8), in: pacific) == nil)
    }

    // MARK: The day's note

    @Test func theDaysNoteIsNamedByThePatternAndByTheStandardOneWhenItCannotBeRead() {
        let day = date(2026, 10, 8)
        #expect(NoteFiles.dayName(format: "dddd, MMMM Do YYYY", now: day, in: pacific) == "Thursday, October 8th 2026.md")
        #expect(NoteFiles.dayName(format: "YYYY/MM/DD", now: day, in: pacific) == "2026/10/08.md")
        #expect(NoteFiles.dayName(format: "YYYY-MM-DD HH", now: day, in: pacific) == "2026-10-08.md", "an hour is not in a day's name: the standard one")
        #expect(NoteFiles.dayName(format: "", now: day, in: pacific) == "2026-10-08.md", "an empty setting is the standard one")
        #expect(NoteFiles.dayName(format: nil, now: day, in: pacific) == "2026-10-08.md")
        #expect(MomentPattern.text(MomentPattern.standard, for: day, in: pacific) == "2026-10-08")
    }

    @Test func aVaultsOwnFormatAndFolderDecideWhereALineLands() throws {
        let now = Date()
        let set = try scratchVault(#"{"folder":"Journal","format":"YYYY/MM/[Day] D"}"#)
        let odd = try scratchVault(#"{"folder":"Journal","format":"YYYY-MM-DD HH:mm"}"#)
        let empty = try scratchVault(#"{"format":""}"#)
        let missing = try scratchVault(#"{"folder":"Journal"}"#)
        let none = try scratchVault(nil)
        let octarine = try scratchVault(#"{"format":"YYYY/MM/[Day] D"}"#)
        try FileManager.default.createDirectory(at: octarine.appendingPathComponent(".octarine"), withIntermediateDirectories: true)
        defer { [set, odd, empty, missing, none, octarine].forEach { try? FileManager.default.removeItem(at: $0) } }
        let standard = NoteFiles.todayName(now: now)
        let named = try #require(MomentPattern.text("YYYY/MM/[Day] D", for: now))

        #expect(NoteFiles.dayFile(in: set, now: now).path == set.appendingPathComponent("Journal/\(named).md").path)
        #expect(NoteFiles.dayFile(in: odd, now: now).path == odd.appendingPathComponent("Journal/\(standard)").path, "a format Floe cannot read: the standard name")
        #expect(NoteFiles.dayFile(in: empty, now: now).path == empty.appendingPathComponent(standard).path)
        #expect(NoteFiles.dayFile(in: missing, now: now).path == missing.appendingPathComponent("Journal/\(standard)").path)
        #expect(NoteFiles.dayFile(in: none, now: now).path == none.appendingPathComponent(standard).path)
        #expect(NoteFiles.dayFile(in: octarine, now: now).path == octarine.appendingPathComponent("Daily/\(standard)").path, "Octarine's folder is not read as a vault")

        #expect(NoteFiles.perform(.today, text: "renew passport", folder: set.path, now: now) == "Added to today’s note")
        #expect(try String(contentsOf: set.appendingPathComponent("Journal/\(named).md"), encoding: .utf8) == "renew passport\n", "the subfolders are made with the day's first line")
    }
}
