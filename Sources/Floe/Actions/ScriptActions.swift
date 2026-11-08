//
//  ScriptActions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import UniformTypeIdentifiers

/// The result a script acts on: what it is, what it is called, and where it is or what it says. Built when the
/// Actions menu is, so it reads nothing from the disk; `SubjectFacts` are read when the script runs.
nonisolated struct ActionSubject: Equatable, Sendable {
    let kind: SubjectKind
    /// What the row is called: the app's or file's name, the link's title or address, or the text's first line.
    let name: String
    /// The app's bundle, the file or folder, or the web address. A text has none.
    let url: URL?
    /// The text itself, on a text.
    let text: String?

    /// A script gets a text up to this many bytes of UTF-8: the environment a process starts with holds about a
    /// megabyte in all, and one emoji can take dozens.
    static let textLimit = 100_000

    init(kind: SubjectKind, name: String, url: URL) {
        self.kind = kind
        self.name = name
        self.url = url
        text = nil
    }

    init(text: String, name: String) {
        kind = .text
        self.name = name
        url = nil
        self.text = text
    }

    /// What a script is told about the result, as environment variables. A value Floe doesn't know is left unset.
    /// Nothing is written into the script's text, so a name with quotes or `$` in it cannot change the command.
    func environment(facts: SubjectFacts, query: String) -> [String: String] {
        var values = [
            "FLOE_SUBJECT": kind.rawValue,
            "FLOE_NAME": name,
            "FLOE_QUERY": query,
        ]
        values["FLOE_URL"] = url?.absoluteString
        switch kind {
        case .app, .file, .folder:
            if let url {
                values.merge(Self.place(of: url)) { $1 }
            }
            values.merge(facts.environment) { $1 }
        case .url:
            values["FLOE_HOST"] = url?.host(percentEncoded: false)
            values["FLOE_SCHEME"] = url?.scheme
        case .text:
            values["FLOE_TEXT"] = text.map(Self.shortened)
        }
        return values.filter { !$0.value.isEmpty || $0.key == "FLOE_QUERY" }
    }

    /// The text within the limit, cut between characters so an emoji is whole or gone.
    private static func shortened(_ text: String) -> String {
        guard text.utf8.count > textLimit else { return text }
        var end = text.startIndex
        var bytes = 0
        for index in text.indices {
            bytes += text[index].utf8.count
            guard bytes <= textLimit else { break }
            end = text.index(after: index)
        }
        return String(text[..<end])
    }

    /// Where a file is and what its name is made of. The startup disk is only a path: it has no parent, and its
    /// name is the row's.
    private static func place(of url: URL) -> [String: String] {
        let file = url.standardizedFileURL
        guard file.path(percentEncoded: false) != "/" else { return ["FLOE_PATH": "/"] }
        return [
            "FLOE_PATH": plainPath(file),
            "FLOE_FILENAME": file.lastPathComponent,
            "FLOE_BASENAME": file.deletingPathExtension().lastPathComponent,
            "FLOE_EXTENSION": file.pathExtension,
            "FLOE_PARENT": plainPath(file.deletingLastPathComponent()),
        ]
    }

    /// A folder's URL ends in a slash, which a script joining paths would double.
    private static func plainPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

extension ActionSubject {
    /// The result a script acts on, or nil for a result that is not an app, a file, a folder, a link or a text. A
    /// snippet's text is as written, before its placeholders are filled.
    static func of(_ item: RootItem, kind: SubjectKind) -> ActionSubject? {
        switch item {
        case let .app(app): ActionSubject(kind: kind, name: app.name, url: app.url)
        case let .file(file): ActionSubject(kind: kind, name: file.name, url: file.url)
        case let .webAddress(address): ActionSubject(kind: kind, name: address.text, url: address.url)
        case let .bookmark(bookmark): ActionSubject(kind: kind, name: bookmark.title, url: bookmark.url)
        case let .clipboardEntry(entry): entry.text.map { ActionSubject(text: $0, name: entry.title) }
        case let .snippet(snippet): ActionSubject(text: snippet.text, name: snippet.name)
        default: nil
        }
    }

    /// The result with a symbolic link read through to what it points at, as its kind is: what the script acts on.
    /// Its path and its facts then name the same item. Off the main actor, since it asks the disk.
    @concurrent
    func resolved() async -> ActionSubject {
        guard kind != .url, let url else { return self }
        return ActionSubject(kind: kind, name: name, url: url.resolvingSymlinksInPath())
    }
}

/// What is read about a result from the disk and the running apps when a script runs on it.
nonisolated struct SubjectFacts: Equatable, Sendable {
    /// A uniform type identifier, such as `com.adobe.pdf`.
    var contentType: UTType?
    /// A file's size in bytes. Folders and apps have none: adding up what is in them could take long.
    var size: Int?
    var created: Date?
    var modified: Date?
    var bundleIdentifier: String?
    var version: String?
    var build: String?
    /// An app's process, while it runs.
    var process: AppProcess?

    /// A running app's process, as a script is told of it.
    nonisolated struct AppProcess: Equatable, Sendable {
        var pid: pid_t
        var isHidden: Bool
    }

    var environment: [String: String] {
        var values: [String: String] = [:]
        values["FLOE_CONTENT_TYPE"] = contentType?.identifier
        values["FLOE_TYPE_DESCRIPTION"] = contentType?.localizedDescription
        values["FLOE_MIME_TYPE"] = contentType?.preferredMIMEType
        values["FLOE_SIZE"] = size.map(String.init)
        values["FLOE_CREATED"] = created?.formatted(.iso8601)
        values["FLOE_MODIFIED"] = modified?.formatted(.iso8601)
        values["FLOE_BUNDLE_ID"] = bundleIdentifier
        values["FLOE_APP_VERSION"] = version
        values["FLOE_APP_BUILD"] = build
        if bundleIdentifier != nil {
            values["FLOE_APP_RUNNING"] = process == nil ? "0" : "1"
        }
        if let process {
            values["FLOE_APP_PID"] = String(process.pid)
            values["FLOE_APP_HIDDEN"] = process.isHidden ? "1" : "0"
        }
        return values
    }
}

extension SubjectFacts {
    /// Reads what the disk says about the result, off the main actor: a file on a slow or sleeping volume can
    /// take a while to answer. `process` is the app's, read on the main actor first. A link or a text has nothing to read.
    @concurrent
    static func read(_ subject: ActionSubject, process: AppProcess? = nil) async -> SubjectFacts {
        guard subject.kind != .url, let target = subject.url else { return SubjectFacts() }
        let keys: Set<URLResourceKey> = [.contentTypeKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        let values = try? target.resourceValues(forKeys: keys)
        var facts = SubjectFacts(
            contentType: values?.contentType,
            size: subject.kind == .file ? values?.fileSize : nil,
            created: values?.creationDate,
            modified: values?.contentModificationDate
        )
        if subject.kind == .app, let bundle = Bundle(url: target) {
            facts.bundleIdentifier = bundle.bundleIdentifier
            facts.version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            facts.build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            facts.process = process
        }
        return facts
    }

    /// An app's process while it runs, from the running apps the main actor keeps. Nil for any other result.
    @MainActor
    static func process(of subject: ActionSubject) -> AppProcess? {
        guard subject.kind == .app, let url = subject.url else { return nil }
        return AppActions.running(AppEntry(name: subject.name, url: url)).map { AppProcess(pid: $0.processIdentifier, isHidden: $0.isHidden) }
    }

    /// What a script is told about a result, read when it starts: after it was confirmed, so a running app's
    /// process is the one it acts on. A link is read through first, and its app looked up by both paths. A volume
    /// that stopped answering can keep a read waiting for good, so after `limit` the script is told what the
    /// result's row knows, and the disk's facts are left unset.
    @MainActor
    static func environment(of subject: ActionSubject, query: String, limit: Duration = .seconds(10)) async -> [String: String] {
        // Only the disk is asked within the limit, in one piece off the main actor: the limit is for the disk, not
        // for a turn on the main actor. The running app is the main actor's, read after.
        var (target, facts) = await waitAtMost(limit, otherwise: (subject, SubjectFacts())) { @concurrent in
            let target = await subject.resolved()
            return (target, await read(target))
        }
        if facts.bundleIdentifier != nil {
            facts.process = process(of: target) ?? process(of: subject)
        }
        return target.environment(facts: facts, query: query)
    }
}

nonisolated extension SubjectKind {
    /// The kinds a `@floe.subjects` line names, written with commas, spaces or both. Links can be named either way.
    static func list(_ text: String) -> Result<Set<SubjectKind>, ScriptParseError> {
        var kinds: Set<SubjectKind> = []
        for word in text.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let name = word.lowercased()
            guard let kind = name == "link" ? .url : SubjectKind(rawValue: name) else {
                return .failure(.unknownSubject(String(word)))
            }
            kinds.insert(kind)
        }
        return kinds.isEmpty ? .failure(.noSubjects) : .success(kinds)
    }
}

extension ScriptCommand {
    /// The id the script has as a row of an Actions menu, which the user's choices are kept under.
    var actionID: ActionID {
        ActionID(rawValue: RootItem.script(self).id)
    }

    /// The kinds the script acts on, as the Scripts tab lists it: "Actions on Apps and Files".
    func actsOnLabel(locale: Locale = .autoupdatingCurrent) -> String {
        let kinds = SubjectKind.allCases.filter(subjects.contains).map(\.title)
        let list = kinds.formatted(.list(type: .and).locale(locale))
        return String(localized: "Actions on \(list)", bundle: .floe, comment: "Beside a script in Settings. The placeholder lists kinds of result, such as Apps and Files.")
    }
}

extension ActionID {
    var isScript: Bool {
        rawValue.hasPrefix(ScriptCommand.itemPrefix)
    }
}

extension KindActions {
    /// These choices without the keys left on any script but `offered`. A script renamed or taken away keeps its
    /// choices, so they are back if it is, but its keys go to no row while it is not on offer.
    func keeping(scripts offered: Set<ActionID>) -> KindActions {
        var kept = self
        kept.shortcuts = shortcuts.filter { !$0.key.isScript || offered.contains($0.key) }
        return kept
    }
}

extension [ScriptCommand] {
    /// The scripts that act on a kind of result.
    func acting(on kind: SubjectKind) -> [ScriptCommand] {
        filter { $0.subjects.contains(kind) }
    }
}
