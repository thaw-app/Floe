//
//  SessionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Drives a session with the messages a host would send, without starting a process.
@MainActor
struct ExtensionSessionTests {
    /// What the session sent to the host and handed back to the model.
    private final class Recorder {
        var sent: [[String: Any]] = []
        var forwarded: [[String: Any]] = []

        func sentEvents(_ prop: String) -> [[String: Any]] {
            sent.filter { $0["type"] as? String == "event" && $0["prop"] as? String == prop }
        }
    }

    private let session = ExtensionSession(command: Fixture.command("planets"), arguments: ["text": "hi"])
    private let recorder = Recorder()

    init() {
        session.transport = { [recorder] in recorder.sent.append($0) }
        session.onMessage = { [recorder] in recorder.forwarded.append($0) }
    }

    private func render(_ view: [String: Any], screenID: Int = 50) {
        apply(["type": "render", "tree": Fixture.node("root", id: 0, children: [Fixture.node("_screen", id: screenID, children: [view])])])
    }

    /// Serializes a message the way the host sends it and applies it through the production parser.
    private func apply(_ json: [String: Any]) {
        guard let encoded = try? JSONSerialization.data(withJSONObject: json),
              let message = DecodedHostMessage.decode(encoded)
        else {
            Issue.record("the test message \(json["type"] as? String ?? "") is not representable")
            return
        }
        session.apply(message)
    }

    @Test func whatTheExtensionReachedIsRecordedUnderItsNameAndNotHandedOn() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-session-access-\(UUID().uuidString)/ExtensionAccess.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        session.accessStore = ExtensionAccessStore(file: file)
        apply(["type": "access", "hosts": ["hnrss.org"], "programs": ["git"]])
        let recorded = session.accessStore.access(of: session.command.extensionName)
        #expect(recorded.hosts == ["hnrss.org"])
        #expect(recorded.programs == ["git"])
        #expect(recorder.forwarded.isEmpty, "the record is the session's, not the launcher's to act on")
    }

    private var planets: [String: Any] {
        Fixture.node("List", id: 60, children: [
            Fixture.item("Mercury", id: 1, actions: [Fixture.action("Show", id: 11), Fixture.action("Copy", id: 12)]),
            Fixture.item("Venus", id: 2, actions: [
                Fixture.action("Show", id: 21),
                Fixture.node("ActionPanel.Submenu", id: 22, props: ["title": "More"], handlers: ["onOpen"], children: [Fixture.action("Inner", id: 23)]),
            ]),
            Fixture.item("Mars", id: 3),
        ])
    }

    // MARK: Rendering

    @Test func keepsItsCommandAndArguments() {
        #expect(session.command.id == "sample/planets")
        #expect(session.arguments["text"] as? String == "hi")
        #expect(session.view == nil)
        #expect(session.rows.isEmpty)
    }

    @Test func aRenderShowsTheViewAndItsRows() {
        render(planets)
        #expect(session.view?.id == 60)
        #expect(session.isList)
        #expect(session.rows.map(\.id) == [1, 2, 3])
        #expect(session.selectedRow?.id == 1)
        #expect(session.actions.map(\.id) == [11, 12])
    }

    @Test func typingFiltersRowsAndResetsTheSelection() {
        render(planets)
        session.selection = 2
        session.searchText = "ma"
        #expect(session.rows.map(\.id) == [3])
        #expect(session.selection == 0)
        #expect(recorder.sent.isEmpty, "a list that filters itself does not ask the extension")
    }

    @Test func typingIsSentToAListThatHandlesSearchItself() {
        render(Fixture.node("List", id: 61, handlers: ["onSearchTextChange"], children: [Fixture.item("Mercury", id: 1)]))
        session.searchText = "swift"
        session.searchText = "swift"
        let events = recorder.sentEvents("onSearchTextChange")
        #expect(events.count == 1, "the same text is not sent twice")
        #expect(events.first?["id"] as? Int == 61)
        #expect(events.first?["args"] as? [String] == ["swift"])
    }

    @Test func aNewScreenClearsTheSearchSelectionAndFormWithoutTellingTheExtension() {
        render(Fixture.node("List", id: 61, handlers: ["onSearchTextChange"], children: [Fixture.item("A", id: 1), Fixture.item("B", id: 2)]))
        session.searchText = "b"
        session.selection = 1
        session.formValues = ["subject": "typed"]
        session.actionMenuOpen = true
        recorder.sent.removeAll()

        render(Fixture.node("Detail", id: 70), screenID: 51)
        #expect(session.searchText.isEmpty)
        #expect(session.selection == 0)
        #expect(session.formValues.isEmpty)
        #expect(session.actionMenuOpen == false)
        #expect(recorder.sent.isEmpty, "clearing the field for a new screen is not a search")
    }

    @Test func aRerenderOfTheSameScreenKeepsWhatTheUserTyped() {
        render(planets)
        session.searchText = "m"
        session.selection = 1
        render(planets)
        #expect(session.searchText == "m")
        #expect(session.selection == 1)
    }

    /// The renderer transmits only the visible screen: root A, pushed B, then A again with fresh rows.
    @Test func singleScreenSnapshotsKeepIdentityAndDropTheHiddenScreen() {
        render(Fixture.node("List", id: 60, children: [Fixture.item("Mercury", id: 1)]), screenID: 50)
        session.searchText = "mer"
        session.selection = 1

        render(Fixture.node("Detail", id: 70, children: [Fixture.slot("actions", Fixture.node("Action", id: 11, props: ["title": "Pushed"]))]), screenID: 51)
        #expect(session.searchText.isEmpty, "a pushed screen resets the search like any screen change")
        #expect(session.actions.map(\.id) == [11])

        render(Fixture.node("List", id: 60, children: [Fixture.item("Mercury", id: 1), Fixture.item("Venus", id: 2)]), screenID: 50)
        #expect(session.screen?.id == 50, "the restored screen keeps its original id")
        #expect(session.view?.id == 60)
        #expect(session.rows.map(\.id) == [1, 2], "the restored screen's latest rows")
        #expect(session.root?.descendants(ofType: "Detail").contains(where: { $0.id == 70 }) != true, "the hidden screen's nodes are gone")
        #expect(session.actions.isEmpty, "the hidden screen's actions are gone")
    }

    // MARK: Toasts and errors

    @Test func aToastIsShownAndHiddenByItsIdentifier() {
        apply(["type": "toast", "id": 4, "style": "animated", "title": "Loading", "message": "planets"])
        #expect(session.toast == ToastState(id: 4, style: "animated", title: "Loading", message: "planets"))
        apply(["type": "toast", "id": 9, "hidden": true])
        #expect(session.toast?.id == 4, "hiding another toast leaves this one")
        apply(["type": "toast", "id": 4, "hidden": true])
        #expect(session.toast == nil)
    }

    @Test func aToastWithoutDetailsGetsDefaults() {
        apply(["type": "toast"])
        #expect(session.toast == ToastState(id: 0, style: "success", title: "", message: nil))
    }

    @Test func aToastWithActionsKeepsTheirTitles() {
        apply(["type": "toast", "id": 5, "style": "success", "title": "Saved", "primaryTitle": "Undo", "secondaryTitle": "Dismiss"])
        #expect(session.toast == ToastState(id: 5, style: "success", title: "Saved", message: nil, primaryTitle: "Undo", secondaryTitle: "Dismiss"))
    }

    @Test func runningAToastActionTellsTheHostAndDismissesTheToast() {
        apply(["type": "toast", "id": 5, "title": "Saved", "primaryTitle": "Undo", "secondaryTitle": "Dismiss"])
        session.runToastAction(primary: true)
        #expect(session.toast == nil)
        #expect(recorder.sent.count == 1)
        #expect(recorder.sent.first?["type"] as? String == "toastAction")
        #expect(recorder.sent.first?["id"] as? Int == 5)
        #expect(recorder.sent.first?["which"] as? String == "primary")
    }

    @Test func aToastActionWithoutThatButtonSendsNothing() {
        apply(["type": "toast", "id": 6, "title": "Plain"])
        session.runToastAction(primary: true)
        #expect(recorder.sent.isEmpty)
        #expect(session.toast?.id == 6)
    }

    // MARK: Confirmation dialogs

    @Test func aConfirmRequestShowsAnInPanelDialog() {
        apply(["type": "request", "id": 20, "method": "alert.confirm", "params": ["title": "Delete?", "message": "Sure?", "primaryTitle": "Delete", "primaryStyle": "destructive", "dismissTitle": "Keep"]])
        #expect(session.alert == AlertState(id: 20, title: "Delete?", message: "Sure?", primaryTitle: "Delete", isDestructive: true, dismissTitle: "Keep"))
        #expect(recorder.forwarded.isEmpty)
        session.resolveAlert(true)
        #expect(session.alert == nil)
        #expect(recorder.sent.count == 1)
        #expect(recorder.sent.first?["type"] as? String == "reply")
        #expect(recorder.sent.first?["id"] as? Int == 20)
        #expect(recorder.sent.first?["result"] as? Bool == true)
    }

    @Test func aNewAlertReplacesTheOldOneAnsweringItFalse() {
        apply(["type": "request", "id": 21, "method": "alert.confirm", "params": ["title": "First"]])
        apply(["type": "request", "id": 22, "method": "alert.confirm", "params": ["title": "Second"]])
        #expect(session.alert?.id == 22)
        #expect(session.alert?.primaryTitle == "OK")
        let replies = recorder.sent.filter { $0["type"] as? String == "reply" }
        #expect(replies.count == 1)
        #expect(replies.first?["id"] as? Int == 21)
        #expect(replies.first?["result"] as? Bool == false)
        session.resolveAlert(false)
        #expect(recorder.sent.filter { $0["type"] as? String == "reply" }.count == 2)
    }

    @Test func answeringTwiceAnswersOnce() {
        apply(["type": "request", "id": 23, "method": "alert.confirm", "params": ["title": "Sure?"]])
        session.resolveAlert(true)
        session.resolveAlert(false)
        #expect(recorder.sent.count == 1)
    }

    @Test func cancellingOrStoppingAnAlertAnswersItFalse() {
        apply(["type": "request", "id": 24, "method": "alert.confirm", "params": ["title": "Sure?"]])
        apply(["type": "cancelRequest", "id": 24])
        #expect(session.alert == nil)
        #expect(recorder.sent.first?["result"] as? Bool == false)

        apply(["type": "request", "id": 25, "method": "alert.confirm", "params": ["title": "Sure?"]])
        session.stop()
        #expect(session.alert == nil)
        let replies = recorder.sent.filter { $0["type"] as? String == "reply" }
        #expect(replies.count == 2)
        #expect(replies.last?["id"] as? Int == 25)
        #expect(replies.last?["result"] as? Bool == false)
    }

    @Test func aNonFatalErrorIsAFailureToastAndTheViewStays() {
        render(planets)
        apply(["type": "error", "message": "Request failed", "fatal": false])
        #expect(session.toast == ToastState(id: -1, style: "failure", title: "Extension error", message: "Request failed"))
        #expect(session.failure == nil)
        #expect(session.rows.count == 3)
    }

    @Test func aFatalErrorBecomesAFailureWithTheStackAndTheLog() {
        session.appendLog(Data("stderr line\n".utf8))
        apply(["type": "error", "message": "Render failed", "stack": "Error: Render failed\n  at Command", "fatal": true])
        #expect(session.failure?.kind == .error)
        #expect(session.failure?.message == "Render failed")
        #expect(session.failure?.details == "Error: Render failed\n  at Command\n\nstderr line\n")
    }

    @Test func anErrorWithoutAMessageStillSaysSomething() {
        apply(["type": "error", "fatal": true])
        #expect(session.failure?.message == "Unknown error")
        #expect(session.failure?.details.isEmpty == true)
    }

    @Test func theLogKeepsOnlyItsTail() {
        session.appendLog(Data(String(repeating: "a", count: 19000).utf8))
        session.appendLog(Data(String(repeating: "b", count: 2000).utf8))
        #expect(session.log.count == 16000)
        #expect(session.log.hasSuffix("bbbb"))
    }

    // MARK: Process outcome and watchdog

    @Test func aCleanExitIsForwardedAsExit() {
        session.processEnded(status: 0, wasSignalled: false)
        #expect(recorder.forwarded.compactMap { $0["type"] as? String } == ["exit"])
        #expect(session.failure == nil)
    }

    @Test(arguments: [(3, false, "exited with status 3"), (9, true, "was killed by signal 9")] as [(Int32, Bool, String)])
    func anythingElseIsACrash(status: Int32, wasSignalled: Bool, how: String) {
        session.appendLog(Data("last words".utf8))
        session.processEnded(status: status, wasSignalled: wasSignalled)
        #expect(session.failure?.kind == .crashed)
        #expect(session.failure?.message == "The extension stopped unexpectedly. It \(how).")
        #expect(session.failure?.details == "last words")
        #expect(recorder.forwarded.compactMap { $0["type"] as? String } == ["crashed"])
    }

    @Test func aProcessWeStoppedIsNotACrash() {
        session.isStopping = true
        session.processEnded(status: 15, wasSignalled: true)
        #expect(session.failure == nil)
        #expect(recorder.forwarded.isEmpty)
    }

    @Test func aCrashAfterAnErrorKeepsTheError() {
        apply(["type": "error", "message": "Render failed", "fatal": true])
        session.processEnded(status: 1, wasSignalled: false)
        #expect(session.failure?.kind == .error)
        #expect(recorder.forwarded.isEmpty)
    }

    @Test func theWatchdogPingsThenReportsAHostThatStopsAnswering() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        session.heartbeat(now: start)
        #expect(recorder.sent.compactMap { $0["type"] as? String } == ["ping"])

        session.heartbeat(now: start + 6)
        #expect(session.failure == nil, "still within the 8 seconds a ping may take")
        #expect(recorder.sent.count == 1, "no second ping while one is outstanding")

        session.heartbeat(now: start + 9)
        #expect(session.failure?.kind == .unresponsive)
    }

    @Test func aPongClearsTheWaitAndAnUnresponsiveFailure() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        session.heartbeat(now: start)
        session.heartbeat(now: start + 9)
        apply(["type": "pong"])
        #expect(session.failure == nil)
        #expect(session.pingSentAt == nil)

        session.heartbeat(now: start + 12)
        #expect(recorder.sent.count == 2, "pinging resumes")
    }

    @Test func aPongDoesNotClearAnErrorOrCrash() {
        apply(["type": "error", "message": "Render failed", "fatal": true])
        apply(["type": "pong"])
        #expect(session.failure?.kind == .error)
    }

    // MARK: Other messages

    @Test func clearSearchBarEmptiesTheField() {
        render(planets)
        session.searchText = "ma"
        apply(["type": "clearSearchBar"])
        #expect(session.searchText.isEmpty)
    }

    @Test(arguments: ["close", "exit", "popToRoot", "hud", "open", "copy", "paste", "openPreferences"])
    func messagesTheSessionDoesNotOwnGoToTheModel(type: String) {
        apply(["type": type, "title": "payload"])
        #expect(recorder.forwarded.count == 1)
        #expect(recorder.forwarded.first?["type"] as? String == type)
        #expect(recorder.forwarded.first?["title"] as? String == "payload")
    }

    // MARK: Requests

    /// The reply the session sent to the host, once the answer is in.
    private func reply() async -> [String: Any]? {
        for _ in 0 ..< 400 {
            if let reply = recorder.sent.first(where: { $0["type"] as? String == "reply" }) {
                return reply
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    @Test func aRequestIsAnsweredWithAReplyCarryingItsIdentifier() async {
        session.answer = { request, _ in
            guard case let .askAI(prompt, model) = request else { return "" }
            return "\(prompt) on \(model ?? "default")"
        }
        apply(["type": "request", "id": 7, "method": "ai.ask", "params": ["prompt": "why?", "model": "Sonnet"]])
        let reply = await reply()
        #expect(reply?["id"] as? Int == 7)
        #expect(reply?["result"] as? String == "why? on Sonnet")
        #expect(reply?["error"] == nil)
        #expect(recorder.forwarded.isEmpty)
    }

    @Test func aRequestIsAnsweredOffTheMainThread() async {
        let threads = ThreadLog()
        session.answer = { _, _ in
            threads.note("answer")
            return "because"
        }
        apply(["type": "request", "id": 8, "method": "ai.ask", "params": ["prompt": "why?"]])
        #expect(await reply()?["result"] as? String == "because")
        #expect(threads.onMain == ["answer": false])
    }

    @Test func textThatArrivesEarlyIsSentInOrderBeforeTheReply() async {
        session.answer = { _, emit in
            await emit("be")
            await emit("cause")
            return "because"
        }
        apply(["type": "request", "id": 12, "method": "ai.ask", "params": ["prompt": "why?"]])
        _ = await reply()
        #expect(recorder.sent.map { $0["type"] as? String } == ["replyChunk", "replyChunk", "reply"])
        #expect(recorder.sent.compactMap { $0["chunk"] as? String } == ["be", "cause"])
        #expect(recorder.sent.allSatisfy { $0["id"] as? Int == 12 })
    }

    @Test func aRequestThatFailsRepliesWithTheError() async {
        session.answer = { _, _ in throw ShellError("not signed in") }
        apply(["type": "request", "id": 8, "method": "ai.ask", "params": ["prompt": "why?"]])
        let reply = await reply()
        #expect(reply?["id"] as? Int == 8)
        #expect(reply?["error"] as? String == "not signed in")
        #expect(reply?["result"] == nil)
    }

    @Test func anExtensionsQuestionIsRefusedWhileOnlyAIOnThisMacIsAllowed() async {
        let fake = FakeAISources()
        session.answer = { request, emit in
            guard case let .askAI(prompt, model) = request else { return "" }
            return try await AIAnswer.answer(prompt, model: model, choice: .tools, localOnly: true, sources: fake.sources, emit: emit)
        }
        apply(["type": "request", "id": 21, "method": "ai.ask", "params": ["prompt": "why?"]])
        let reply = await reply()
        #expect(reply?["error"] as? String == AIAnswer.localOnlyMessage)
        #expect(reply?["result"] == nil)
        #expect(fake.askedSources.isEmpty, "the question went to no source")
    }

    @Test func anExtensionsQuestionIsAnsweredOnThisMacWhileOnlyThatIsAllowed() async {
        let fake = FakeAISources()
        session.answer = { request, emit in
            guard case let .askAI(prompt, model) = request else { return "" }
            return try await AIAnswer.answer(prompt, model: model, choice: .appleIntelligence, localOnly: true, sources: fake.sources, emit: emit)
        }
        apply(["type": "request", "id": 22, "method": "ai.ask", "params": ["prompt": "why?"]])
        let reply = await reply()
        #expect(reply?["result"] as? String == "appleIntelligence")
        #expect(fake.askedSources == [.appleIntelligence])
    }

    @Test func aRequestCarriesTheNameOfTheExtensionThatAsked() async {
        session.answer = { _, _ in AIAnswer.askingExtension ?? "nobody" }
        apply(["type": "request", "id": 23, "method": "ai.ask", "params": ["prompt": "why?"]])
        let reply = await reply()
        #expect(reply?["result"] as? String == session.command.extensionName)
        #expect(AIAnswer.askingExtension == nil, "outside the request there is no extension asking")
    }

    @Test func aRequestTheAppDoesNotKnowIsRefusedAtOnce() {
        session.answer = { _, _ in "unused" }
        apply(["type": "request", "id": 9, "method": "teleport", "params": [:]])
        #expect(recorder.sent.first?["id"] as? Int == 9)
        #expect(recorder.sent.first?["error"] as? String == "Floe can't answer \"teleport\" yet, or the request is missing something it needs.")
        apply(["type": "request", "method": "ai.ask", "params": ["prompt": "no id"]])
        #expect(recorder.sent.count == 1)
    }

    @Test func aCancelledRequestGetsNoReply() async {
        session.answer = { _, _ in
            try await Task.sleep(for: .seconds(30))
            return "too late"
        }
        apply(["type": "request", "id": 10, "method": "ai.ask", "params": ["prompt": "why?"]])
        apply(["type": "cancelRequest", "id": 10])
        apply(["type": "cancelRequest", "id": 99])
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.sent.isEmpty)
    }

    @Test func aHostThatEndsLeavesItsRequestsUnanswered() async {
        session.answer = { _, _ in
            try await Task.sleep(for: .seconds(30))
            return "too late"
        }
        apply(["type": "request", "id": 11, "method": "ai.ask", "params": ["prompt": "why?"]])
        session.processEnded(status: 0, wasSignalled: false)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.sent.isEmpty)
    }

    @Test func theHostStartsWithTheShellsVariablesItsPreferencesAndWhetherAIIsThere() {
        let base = ["PATH": "/opt/homebrew/bin", "FLOE_AI": "stale"]
        let with = ExtensionSession.hostVariables(base, preferences: Data(#"{"unit":"metric"}"#.utf8), hasAI: true)
        #expect(with == [
            "PATH": "/opt/homebrew/bin", "FLOE_PREFERENCES": #"{"unit":"metric"}"#, "FLOE_AI": "1", "FLOE_LAUNCH_TYPE": "userInitiated",
        ])
        let background = ExtensionSession.hostVariables(base, preferences: nil, hasAI: false, launchType: "background")
        #expect(background == ["PATH": "/opt/homebrew/bin", "FLOE_LAUNCH_TYPE": "background"])
    }

    // MARK: Actions

    @Test func runningAnActionSendsItsHandlerAndClosesTheMenu() {
        render(planets)
        session.actionMenuOpen = true
        session.run(session.actions[1])
        #expect(session.actionMenuOpen == false)
        #expect(recorder.sentEvents("onAction").first?["id"] as? Int == 12)
    }

    @Test func anActionWithoutAHandlerSendsNothing() {
        session.run(Fixture.tree(Fixture.node("Action", props: ["title": "Inert"])))
        #expect(recorder.sent.isEmpty)
    }

    @Test func submittingSendsTheFormsValues() throws {
        render(Fixture.node("Form", id: 80, children: [
            Fixture.slot("actions", Fixture.node("ActionPanel", children: [
                Fixture.node("Action", id: 81, props: ["title": "Send", "isSubmit": true], handlers: ["onSubmit"]),
            ])),
            Fixture.node("Form.TextField", id: 82, props: ["id": "subject"], handlers: ["onChange"]),
            Fixture.node("Form.DatePicker", id: 83, props: ["id": "due"], handlers: ["onChange"]),
            Fixture.node("Form.Checkbox", id: 84, props: ["id": "urgent"]),
        ]))
        let fields = try #require(session.view?.content)
        session.setFormValue(fields[0], "Crash")
        session.setFormValue(fields[1], "2026-10-09T00:00:00Z")
        session.setFormValue(fields[2], true)

        #expect(session.formValue(fields[0]) as? String == "Crash")
        let changes = recorder.sentEvents("onChange")
        #expect(changes.count == 2, "a field without onChange is not reported")
        #expect((changes[1]["args"] as? [[String: String]])?.first == ["$date": "2026-10-09T00:00:00Z"])

        session.run(session.actions[0])
        let submitted = try #require((recorder.sentEvents("onSubmit").first?["args"] as? [[String: Any]])?.first)
        #expect(submitted["subject"] as? String == "Crash")
        #expect(submitted["urgent"] as? Bool == true)
        #expect(submitted["due"] as? [String: String] == ["$date": "2026-10-09T00:00:00Z"])
    }

    @Test func aSubmitActionWithoutAHandlerOrAValueWithoutAFieldIdDoesNothing() {
        session.run(Fixture.tree(Fixture.node("Action", props: ["isSubmit": true])))
        session.setFormValue(Fixture.tree(Fixture.node("Form.Separator")), "x")
        #expect(recorder.sent.isEmpty)
        #expect(session.formValues.isEmpty)
    }

    // MARK: Selection and the action menu

    @Test func arrowKeysMoveTheListSelectionAndStopAtTheEnds() {
        render(planets)
        session.moveSelection(by: 1)
        #expect(session.selectedRow?.id == 2)
        session.moveSelection(by: 50)
        #expect(session.selection == 2)
        session.moveSelection(by: -50)
        #expect(session.selection == 0)
    }

    @Test func whileTheMenuIsOpenArrowsMoveWithinIt() {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        session.moveSelection(by: 5)
        #expect(session.actionSelection == 1)
        #expect(session.selection == 1, "the list selection does not move")
        #expect(session.menuEntries.map(\.id) == [21, 22])
    }

    @Test func enteringASubmenuTellsTheExtensionAndListsItsActions() {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        session.actionQuery = "mo"
        session.activateMenuEntry(at: 0)
        #expect(recorder.sentEvents("onAction").first?["id"] as? Int == nil, "the query matched no action, only the submenu's title")

        session.actionQuery = ""
        session.activateMenuEntry(at: 1)
        #expect(recorder.sentEvents("onOpen").first?["id"] as? Int == 22)
        #expect(session.actionPath.map(\.id) == [22])
        #expect(session.menuEntries.map(\.id) == [23])
        #expect(session.actionSelection == 0)

        session.activateMenuEntry(at: 0)
        #expect(recorder.sentEvents("onAction").first?["id"] as? Int == 23)
        #expect(session.actionMenuOpen == false)
        #expect(session.actionPath.isEmpty, "closing the menu leaves the submenu")
    }

    @Test func escapeClearsTheQueryThenLeavesTheSubmenuThenClosesTheMenu() throws {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        let submenu = try #require(session.menuEntries.first { $0.isSubmenu })
        session.openSubmenu(submenu.node)
        session.actionQuery = "inn"

        session.closeSubmenuOrMenu()
        #expect(session.actionQuery.isEmpty)
        #expect(session.actionPath.count == 1)
        session.closeSubmenuOrMenu()
        #expect(session.actionPath.isEmpty)
        #expect(session.actionMenuOpen)
        session.closeSubmenuOrMenu()
        #expect(session.actionMenuOpen == false)
    }

    @Test func anOpenSubmenuThatDisappearsFromTheTreeIsLeft() throws {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        let submenu = try #require(session.menuEntries.first { $0.isSubmenu })
        session.openSubmenu(submenu.node)

        render(planets)
        #expect(session.actionPath.count == 1, "still in the tree, so it stays open")

        render(Fixture.node("List", id: 60, children: [Fixture.item("Mercury", id: 1), Fixture.item("Venus", id: 2, actions: [Fixture.action("Show", id: 21)])]))
        #expect(session.actionPath.isEmpty)
    }

    @Test func activatingAnEntryThatIsNotThereDoesNothing() {
        render(planets)
        session.activateMenuEntry(at: 9)
        #expect(recorder.sent.isEmpty)
    }
}
