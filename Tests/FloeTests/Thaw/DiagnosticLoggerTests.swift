//
//  DiagnosticLoggerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The logger is one shared instance, so these run one at a time and each leaves it switched off.
@Suite(.serialized) struct DiagnosticLoggerTests {
    private let logger = DiagnosticLogger.shared
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-diagnostic-log-\(UUID().uuidString)")
    private let category = "LoggerTests-\(UUID().uuidString)"

    private var file: URL {
        folder.appendingPathComponent("floe.log")
    }

    /// Lines are written on the logger's serial queue, so an empty block run on it returns after them.
    private func written(to file: URL) throws -> String {
        logger.writeQueue.sync {}
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// Other suites log while the file is open; the category picks out this suite's lines.
    private func ownLines(in file: URL) throws -> [String] {
        try written(to: file).split(separator: "\n").map(String.init).filter { $0.contains("[\(category)]") }
    }

    private func stopLogging() {
        logger.writeQueue.sync {}
        logger.isEnabled = false
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func theLogFolderIsFloesOwnInTheUsersLibrary() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(logger.logDirectory == home.appendingPathComponent("Library/Logs/Floe", isDirectory: true))
    }

    @Test func attachingOpensTheFileAndWritesAHeaderNamingTheProcess() throws {
        logger.attachToFile(at: file)
        defer { stopLogging() }

        #expect(logger.isEnabled)
        #expect(logger.currentLogFile == file)
        let text = try written(to: file)
        #expect(text.hasPrefix("========================================\nFloe Diagnostic Log\nStarted: "))
        #expect(text.contains("\nProcess: \(ProcessInfo.processInfo.processName)\n"))
        #expect(text.contains("\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"))
    }

    @Test(arguments: [
        (DiagnosticLogger.Level.debug, "DEBUG"),
        (.info, "INFO"),
        (.notice, "NOTICE"),
        (.warning, "WARNING"),
        (.error, "ERROR"),
    ])
    func aLineCarriesItsTimeItsLevelAndItsCategory(level: DiagnosticLogger.Level, name: String) throws {
        logger.attachToFile(at: file)
        defer { stopLogging() }

        logger.log(level: level, category: category, message: "the catalog loaded")

        let lines = try ownLines(in: file)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.hasSuffix(" [\(name)] [\(category)] the catalog loaded"))
        let stamp = #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \["#
        #expect(line.range(of: stamp, options: .regularExpression) != nil)
    }

    @Test func aMessageWithLineBreaksStaysOneRecord() throws {
        logger.attachToFile(at: file)
        defer { stopLogging() }

        logger.log(level: .error, category: category, message: "failed\n2026-01-01 00:00:00.000 [INFO] [\(category)] forged\r\n")

        let lines = try ownLines(in: file)
        #expect(lines.count == 1)
        #expect(lines.first?.hasSuffix(#"failed\n2026-01-01 00:00:00.000 [INFO] [\#(category)] forged\r\n"#) == true)
    }

    @Test func everyBreakAndControlCharacterIsWrittenAsAnEscape() {
        // Readers that split on Unicode's line and paragraph separators, or a terminal that obeys escape codes,
        // would otherwise see a second record or a rewritten one.
        #expect(DiagnosticLogger.oneLine("a\u{2028}b\u{2029}c\u{85}d") == #"a\u{2028}b\u{2029}c\u{85}d"#)
        #expect(DiagnosticLogger.oneLine("a\u{0B}b\u{0C}c\u{1B}[2Kd\u{7F}\u{0}") == #"a\u{b}b\u{c}c\u{1b}[2Kd\u{7f}\u{0}"#)
        #expect(DiagnosticLogger.oneLine("tab\tend") == #"tab\tend"#)
        // A backslash is doubled, so a message that spells out an escape cannot pass for one.
        #expect(DiagnosticLogger.oneLine(#"C:\new"#) == #"C:\\new"#)
        #expect(DiagnosticLogger.oneLine("caf\u{E9} \u{1F600}") == "caf\u{E9} \u{1F600}")
    }

    @Test func eachDiagLogMethodWritesALineAtItsOwnLevel() throws {
        logger.attachToFile(at: file)
        defer { stopLogging() }
        let log = DiagLog(category: category)

        log.debug("one")
        log.info("two")
        log.notice("three")
        log.warning("four")
        log.error("five")

        let endings = try ownLines(in: file).map { String($0.dropFirst("2026-01-01 00:00:00.000 ".count)) }
        #expect(endings == [
            "[DEBUG] [\(category)] one",
            "[INFO] [\(category)] two",
            "[NOTICE] [\(category)] three",
            "[WARNING] [\(category)] four",
            "[ERROR] [\(category)] five",
        ])
    }

    @Test func aMessageIsBuiltOnceWhileTheFileIsOpen() {
        logger.attachToFile(at: file)
        defer { stopLogging() }
        var built = 0

        DiagLog(category: category).debug({ built += 1; return "counted" }())

        #expect(built == 1)
    }

    @Test func turningLoggingOffClosesTheFileAndNothingMoreIsWritten() throws {
        logger.attachToFile(at: file)
        defer { stopLogging() }
        logger.log(level: .info, category: category, message: "before")
        let open = try written(to: file)

        logger.isEnabled = false

        #expect(!logger.isEnabled)
        #expect(logger.currentLogFile == nil)
        let closed = try written(to: file)
        #expect(closed.hasPrefix(open))
        #expect(closed.hasSuffix(" [DiagnosticLogger] Diagnostic logging stopped\n"))

        logger.log(level: .error, category: category, message: "after")
        DiagLog(category: category).error("after")

        #expect(try written(to: file) == closed)
    }

    @Test func attachingToAFileThatHasTextAddsToItsEnd() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("written by the main app\n".utf8).write(to: file)

        logger.attachToFile(at: file)
        defer { stopLogging() }
        logger.log(level: .info, category: category, message: "written by the helper")

        let text = try written(to: file)
        #expect(text.hasPrefix("written by the main app\n========================================\nFloe Diagnostic Log\n"))
        #expect(text.hasSuffix(" [INFO] [\(category)] written by the helper\n"))
    }

    @Test func attachingAgainClosesTheFirstFileAndWritesToTheSecond() throws {
        let second = folder.appendingPathComponent("second.log")
        logger.attachToFile(at: file)
        defer { stopLogging() }
        logger.log(level: .info, category: category, message: "to the first")
        _ = try written(to: file)

        logger.attachToFile(at: second)
        logger.log(level: .info, category: category, message: "to the second")

        #expect(logger.isEnabled)
        #expect(logger.currentLogFile == second)
        #expect(try ownLines(in: second).map { String($0.suffix(13)) } == ["to the second"])
        #expect(try ownLines(in: file).map { String($0.suffix(12)) } == ["to the first"])
        #expect(try written(to: file).hasSuffix(" [DiagnosticLogger] Diagnostic logging stopped\n"))
    }

    @Test func openingAFileKeepsTheFiveNewestLogsAndLeavesOtherFilesAlone() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for age in 1 ... 7 {
            let old = folder.appendingPathComponent("old-\(age).log")
            try Data().write(to: old)
            let created = Date(timeIntervalSince1970: 1_700_000_000 - Double(age) * 86400)
            try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: old.path)
        }
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        logger.attachToFile(at: file)
        defer { stopLogging() }
        logger.writeQueue.sync {}

        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(kept == ["floe.log", "notes.txt", "old-1.log", "old-2.log", "old-3.log", "old-4.log"])
    }

    @Test func aFolderThatCannotBeMadeLeavesLoggingOff() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { stopLogging() }
        let notAFolder = folder.appendingPathComponent("taken")
        try Data().write(to: notAFolder)

        logger.attachToFile(at: notAFolder.appendingPathComponent("floe.log"))

        #expect(!logger.isEnabled)
        #expect(logger.currentLogFile == nil)
    }

    @Test func aPathThatCannotBeOpenedForWritingLeavesLoggingOff() throws {
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        defer { stopLogging() }

        logger.attachToFile(at: file)

        #expect(!logger.isEnabled)
        #expect(logger.currentLogFile == nil)
    }
}
