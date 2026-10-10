//
//  Session+Requests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The half of a session that answers what the extension asks the app for, and what its host starts with.
extension ExtensionSession {
    /// Takes `request` and `cancelRequest`; false for any other message.
    func handleRequest(_ fields: [String: Any]) -> Bool {
        switch fields["type"] as? String {
        case "request":
            if fields["method"] as? String == "alert.confirm", let id = fields["id"] as? Int {
                showAlert(id: id, params: fields["params"] as? [String: Any] ?? [:])
            } else {
                answerRequest(fields)
            }
        case "cancelRequest":
            if let id = fields["id"] as? Int {
                if alert?.id == id {
                    resolveAlert(false)
                }
                pendingRequests.removeValue(forKey: id)?.cancel()
            }
        default:
            return false
        }
        return true
    }

    /// Starts answering one request and replies when the answer is there, after any `replyChunk`s. A request the host
    /// cancelled, or one cut off because the session stopped, gets no reply: nobody is waiting.
    private func answerRequest(_ fields: [String: Any]) {
        guard let id = fields["id"] as? Int else { return }
        let method = fields["method"] as? String ?? ""
        guard let request = HostRequest(method: method, params: fields["params"] as? [String: Any] ?? [:]) else {
            send(["type": "reply", "id": id, "error": "Floe can't answer \"\(method)\" yet, or the request is missing something it needs."])
            return
        }
        let answer = answer
        let extensionName = command.extensionName
        // Text that arrives early is sent on in order, while the request is still wanted.
        let emit: @Sendable (String) async -> Void = { [weak self] text in
            await MainActor.run { [weak self] in
                guard let self, pendingRequests[id] != nil else { return }
                send(["type": "replyChunk", "id": id, "chunk": text])
            }
        }
        pendingRequests[id] = Task { @MainActor [weak self] in
            var reply: [String: Any] = ["type": "reply", "id": id]
            do {
                if request.isOAuth {
                    guard let self else { throw OAuthError.cancelled }
                    if let lent = await OAuthBroker.lent(request, extensionName: command.extensionName, extensionTitle: command.extensionTitle) {
                        reply["result"] = lent
                    } else if OAuthBroker.isParked {
                        // An extension asks for its tokens before anything else: with none to give, that is no error.
                        guard request.asksOnlyForTokens else { throw OAuthError.cancelled }
                        reply["result"] = NSNull()
                    } else {
                        reply["result"] = try await OAuthBroker.shared.perform(request, extensionName: command.extensionName)
                    }
                } else {
                    // The extension's name travels with the request, for the AI source it may be pinned to.
                    let result: Any = try await AIAnswer.$askingExtension.withValue(extensionName) {
                        try await answer(request, emit)
                    }
                    reply["result"] = result
                }
            } catch {
                reply["error"] = error.localizedDescription
            }
            guard let self, pendingRequests.removeValue(forKey: id) != nil else { return }
            send(reply)
        }
    }

    /// Stops answering, when the host is going away. A waiting sign-in fails too: the browser's
    /// callback would otherwise answer a session that is no longer there.
    func cancelRequests() {
        OAuthBroker.shared.cancelAll(for: command.extensionName)
        for task in pendingRequests.values {
            task.cancel()
        }
        pendingRequests = [:]
    }

    // MARK: Alerts and toast actions

    /// Shows a `confirmAlert` dialog. A new alert replaces an open one, answering the old request false.
    func showAlert(id: Int, params: [String: Any]) {
        resolveAlert(false)
        alert = AlertState(
            id: id,
            title: params["title"] as? String ?? "",
            message: params["message"] as? String,
            primaryTitle: params["primaryTitle"] as? String ?? String(localized: "OK", bundle: .floe),
            isDestructive: (params["primaryStyle"] as? String) == "destructive",
            dismissTitle: params["dismissTitle"] as? String ?? String(localized: "Cancel", bundle: .floe)
        )
    }

    /// Answers the open `alert.confirm` request and dismisses the dialog. Later answers are ignored.
    func resolveAlert(_ confirmed: Bool) {
        guard let current = alert else { return }
        alert = nil
        send(["type": "reply", "id": current.id, "result": confirmed])
    }

    /// Tells the host a toast action was clicked, then dismisses the toast.
    func runToastAction(primary: Bool) {
        guard let toast else { return }
        guard (primary ? toast.primaryTitle : toast.secondaryTitle) != nil else { return }
        send(["type": "toastAction", "id": toast.id, "which": primary ? "primary" : "secondary"])
        self.toast = nil
    }

    /// The variable that tells the host not to watch what the extension reaches, and the value that says so.
    static let developmentVariable = "FLOE_DEVELOPMENT"
    static let accessVariable = "FLOE_ACCESS"
    static let accessOff = "off"

    /// What the host starts with: the login shell's environment, the command's preferences, whether `AI.ask`
    /// has a tool to run on, and whether what the extension reaches is recorded.
    static func hostVariables(_ base: [String: String], preferences: Data?, hasAI: Bool, launchType: String = "userInitiated", recordsAccess: Bool = true, isDevelopment: Bool = false) -> [String: String] {
        var variables = base
        // Preferences go through the environment so the host has them before the command's first line runs.
        if let preferences {
            variables["FLOE_PREFERENCES"] = String(bytes: preferences, encoding: .utf8)
        }
        variables["FLOE_AI"] = hasAI ? "1" : nil
        variables["FLOE_OAUTH"] = OAuthBroker.isParked ? nil : "1"
        variables["FLOE_LAUNCH_TYPE"] = launchType
        variables[accessVariable] = recordsAccess ? nil : accessOff
        variables[developmentVariable] = isDevelopment ? "1" : nil
        return variables
    }

    /// Whether an extension is one being worked on in the checkout, and not one that was installed.
    static func isUnderDevelopment(_ folder: URL, developmentFolder: URL? = Paths.developmentExtensions) -> Bool {
        guard let developmentFolder else { return false }
        return folder.standardizedFileURL.path.hasPrefix(developmentFolder.standardizedFileURL.path + "/")
    }
}
