//
//  ProcessesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

@MainActor
struct ProcessesTests {
    private let notch = RunningProcess(pid: 400, path: "/Users/me/Thaw/.build/debug/ThawNotch", memory: 80 << 20)
    private let thaw = RunningProcess(pid: 300, path: "/Applications/Thaw.app/Contents/MacOS/Thaw", memory: 200 << 20)
    private let helper = RunningProcess(pid: 310, path: "/Applications/Thaw.app/Contents/XPCServices/Capture.xpc/Contents/MacOS/Capture", memory: 30 << 20)
    private let finder = RunningProcess(pid: 200, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", memory: 150 << 20)

    @Test(arguments: [("kill thawnotch", "thawnotch"), ("Kill  Thaw Notch ", "Thaw Notch"), ("kill 400", "400")])
    func theKeywordAndANameAskForProcesses(query: String, name: String) {
        #expect(Processes.name(in: query) == name)
    }

    @Test(arguments: ["kill", "kill ", "killall thaw", "skill thaw", "thaw kill"])
    func anythingElseIsAnOrdinarySearch(query: String) {
        #expect(Processes.name(in: query) == nil)
    }

    @Test(arguments: [("port 3000", 3000), ("Port  8080 ", 8080), ("port 80", 80), ("port 65535", 65535)])
    func thePortKeywordAndANumberAskWhoListensThere(query: String, port: Int) {
        #expect(Processes.port(in: query) == port)
    }

    @Test(arguments: ["port", "port 3", "port 70000", "port abc", "port 30 00", "ports 3000", "3000"])
    func whatIsNoPortIsAnOrdinarySearch(query: String) {
        #expect(Processes.port(in: query) == nil)
    }

    @Test func theListenersOnAPortAreFoundOffTheMainThreadAndShownAsProcessRows() async {
        #expect(Processes.pids(in: "400\n300\n400\n\nnot a number\n") == [400, 300])
        var scope = PortSearchScope()
        scope.running = { [notch, thaw, finder] in [notch, thaw, finder] }
        let onMain = Mutex<Bool?>(nil)
        scope.listening = { port in
            onMain.withLock { $0 = Thread.isMainThread }
            return port == 3000 ? [400] : []
        }
        #expect(scope.text(in: SearchContext(query: "port 3000")) == "3000")
        #expect(scope.text(in: SearchContext(query: "port authority")) == nil, "an ordinary search is left alone")
        #expect(scope.results(for: "3000", context: SearchContext(query: "port 3000")).isEmpty, "nothing is known at once")

        var found: [[String]] = []
        if let stream = scope.updates(for: "3000", context: SearchContext(query: "port 3000")) {
            for await rows in stream {
                found.append(rows.map(\.title))
            }
        }
        #expect(found == [["ThawNotch"]])
        #expect(onMain.withLock { $0 } == false)
        let unasked = scope.updates(for: "x", context: SearchContext(query: "port x"))
        #expect(unasked == nil)
        #expect(Processes.listening(on: 1).isEmpty, "nothing listens on port 1, and asking is safe")
    }

    @Test func thoseNamedSoComeFirstThenThoseThatOnlyRunFromThere() {
        let all = [finder, helper, notch, thaw]
        #expect(Processes.matching("thaw", in: all, excluding: 1).map(\.pid) == [300, 400, 310], "by name and memory, then the helper inside Thaw.app")
        #expect(Processes.matching("THAWNOTCH", in: all, excluding: 1).map(\.pid) == [400])
        #expect(Processes.matching("thaw", in: all, excluding: 300).map(\.pid) == [400, 310], "never the launcher itself")
        #expect(Processes.matching("nothing", in: all, excluding: 1).isEmpty)
        let many = (0 ..< 20).map { RunningProcess(pid: 1000 + $0, path: "/usr/bin/node", memory: UInt64($0)) }
        #expect(Processes.matching("node", in: many, excluding: 1).count == Processes.limit)
        #expect(Processes.matching("launchd", in: [RunningProcess(pid: 1, path: "/sbin/launchd", memory: 1)], excluding: 99).isEmpty, "the first process is not offered")
    }

    @Test func aProcessSaysItsNameItsAppAndWhatTellsItApart() {
        #expect(notch.name == "ThawNotch")
        #expect(notch.bundlePath == nil)
        #expect(helper.bundlePath == "/Applications/Thaw.app")
        #expect(Processes.label(for: RunningProcess(pid: 42, path: "/bin/x", memory: 0)).hasPrefix("PID 42 · "))
        let item = RootItem.process(notch)
        #expect(item.id == "process:400")
        #expect(item.title == "ThawNotch")
        #expect(item.kind == "Process")
        #expect(item.rowLabel == Processes.label(for: notch))
        #expect(item.isScopeResult, "found just now: no favorite, no usage record")
    }

    @Test func theRunningListHasThisProcessInIt() {
        Processes.forget()
        let running = Processes.running()
        let own = running.first { $0.pid == getpid() }
        #expect(own != nil)
        #expect((own?.memory ?? 0) > 0)
        #expect(own?.path.hasPrefix("/") == true)
    }

    @Test func theScopeListsMatchesAndIsAmongTheScopesTheSearchKnows() {
        var scope = ProcessSearchScope()
        scope.running = { [notch, thaw, finder] in [notch, thaw, finder] }
        #expect(scope.results(for: "thaw", context: SearchContext(query: "kill thaw")).map(\.title) == ["Thaw", "ThawNotch"])
        #expect(scope.text(in: SearchContext(query: "kill thaw")) == "thaw")
        #expect(scope.text(in: SearchContext(query: "thaw")) == nil)
        #expect(scope.title == "Running Processes")
        let keywords = RootSearch.standardScopes().map(\.keyword)
        #expect(keywords.contains("kill") && keywords.contains("port"))
    }

    @Test func returnAsksAProcessToQuitAndTheActionForcesIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-process-tests-\(UUID().uuidString)"))
        let model = LauncherModel(settings: AppSettings(defaults: defaults), usage: UsageStore(defaults: defaults), snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("floe-receipts-\(UUID().uuidString).json"))
        var ended: [String] = []
        var refuse = false
        model.shell.endProcess = { process, force in
            ended.append("\(process.pid) \(force ? "forced" : "asked")")
            return !refuse
        }
        var said: [String] = []
        model.showHUD = { said.append($0) }
        let item = RootItem.process(notch)

        #expect(model.primaryActionTitle(for: item) == "Quit")
        #expect(model.rootActions(for: item).map { $0?.title ?? "-" } == ["Quit", "Force Quit…", "-", "Show in Finder", "Copy Process ID"])
        model.activate(item)
        model.shell.confirmsForceQuit = { _ in false }
        model.rootActions(for: item)[1]?.run()
        #expect(ended == ["400 asked"], "a no to the question ends nothing")
        model.shell.confirmsForceQuit = { _ in true }
        model.rootActions(for: item)[1]?.run()
        refuse = true
        model.activate(item)
        #expect(ended == ["400 asked", "400 forced", "400 asked"])
        #expect(said == ["Quitting ThawNotch", "Forced ThawNotch to quit", "Couldn't quit ThawNotch"])
    }
}
