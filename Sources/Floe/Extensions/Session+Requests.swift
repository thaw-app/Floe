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
            let params = fields["params"] as? [String: Any] ?? [:]
            let method = fields["method"] as? String ?? ""
            guard let id = fields["id"] as? Int else { break }
            switch method {
            case "alert.confirm": showAlert(id: id, params: params)
            case "command.launch": reply(to: id) { try launch(params) }
            case "snippet.create", "quicklink.create": reply(to: id) { try ExtensionCreations.create(method, params) }
            default: answerRequest(fields)
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

    /// Answers a request the app settles at once: null when `body` returns, its error when it throws.
    private func reply(to id: Int, _ body: () throws -> Void) {
        var reply: [String: Any] = ["type": "reply", "id": id]
        do {
            try body()
            reply["result"] = NSNull()
        } catch {
            reply["error"] = error.localizedDescription
        }
        send(reply)
    }

    /// `launchCommand`, which starts the command before it answers.
    private func launch(_ params: [String: Any]) throws {
        guard let launcher = CommandLauncher.shared else {
            throw RequestRefusal(errorDescription: "Floe can't launch commands from here.")
        }
        try launcher.launch(params, from: command)
    }

    /// Takes `toggleQuickLook`, for the selected item's `quickLook` file; false for any other message.
    func toggledQuickLook(_ fields: [String: Any]) -> Bool {
        guard fields["type"] as? String == "toggleQuickLook" else { return false }
        if let url = Self.quickLookFile(of: selectedRow) {
            QuickLookPresenter.shared.toggle(url)
        }
        return true
    }

    /// The file an item names in its `quickLook` prop, as `{ path, name }`.
    static func quickLookFile(of row: Row?) -> URL? {
        guard let quickLook = row?.node.props["quickLook"] as? [String: Any], let path = quickLook["path"] as? String, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
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
                        reply["result"] = try await OAuthBroker.shared.perform(request, extensionName: command.extensionName, installation: command.extensionDir)
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
            dismissTitle: params["dismissTitle"] as? String ?? String(localized: "Cancel", bundle: .floe),
            icon: params["icon"]
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
        guard let toast, (primary ? toast.primaryTitle : toast.secondaryTitle) != nil else { return }
        send(["type": "toastAction", "id": toast.id, "which": primary ? "primary" : "secondary"])
        self.toast = nil
    }

    /// The variable that tells the host not to watch what the extension reaches, and the value that says so.
    static let developmentVariable = "FLOE_DEVELOPMENT"
    static let accessVariable = "FLOE_ACCESS"
    /// Tells the host which render references this app reads; a host that writes another kind sends whole renders.
    static let referencesVariable = "FLOE_RENDER_REFERENCES"
    static let accessOff = "off"
    /// Tells the host whether the app is drawn light or dark, for environment.appearance.
    static let appearanceVariable = "FLOE_APPEARANCE"

    /// What a command may use that the app has to allow, told to it through `environment.canAccess`.
    nonisolated struct HostGrants: OptionSet, Sendable {
        let rawValue: Int
        /// `AI.ask` has a tool or an API to run on.
        static let ai = HostGrants(rawValue: 1 << 0)
        /// Floe has Accessibility access, which `WindowManagement` needs.
        static let windows = HostGrants(rawValue: 1 << 1)
    }

    /// The host's first line of input: the command's preferences, with their Keychain values, and the storage key.
    /// They never go in the environment, which another program running as the user can read with ps.
    static func secretsLine(preferences: Data?, storage: StorageKey.Access) -> [UInt8] {
        var message: [String: Any] = ["type": "secrets"]
        message["preferences"] = preferences.flatMap { String(bytes: $0, encoding: .utf8) }
        if case let .key(key) = storage {
            message["storageKey"] = key
        }
        message["storageLocked"] = storage == .unavailable
        let data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data(#"{"type":"secrets"}"#.utf8)
        return Array(data) + [0x0A]
    }

    /// What the host starts with: the login shell's environment as `ExtensionEnvironment` limits it, the command's
    /// preferences, what it may use, whether what the extension reaches is recorded, and the app's appearance.
    static func hostVariables(
        _ base: [String: String],
        passesShellEnvironment: Bool = false,
        grants: HostGrants,
        launch: (type: String, context: [String: Any]?, fallbackText: String?) = ("userInitiated", nil, nil),
        recordsAccess: Bool = true,
        isDevelopment: Bool = false,
        isDark: Bool? = nil
    ) -> [String: String] {
        var variables = ExtensionEnvironment.handedOn(base, passesShellEnvironment: passesShellEnvironment)
        // React picks its build from this. An extension being worked on keeps the development build and its
        // warnings, and a value the shell already holds is left as it is.
        if !isDevelopment, variables["NODE_ENV"] == nil {
            variables["NODE_ENV"] = "production"
        }
        // The passwords and the storage key come on the host's input: see secretsLine.
        variables["FLOE_SECRETS"] = "input"
        variables["FLOE_PREFERENCES"] = nil
        variables["FLOE_AI"] = grants.contains(.ai) ? "1" : nil
        variables["FLOE_WINDOWS"] = grants.contains(.windows) ? "1" : nil
        variables["FLOE_OAUTH"] = OAuthBroker.isParked ? nil : "1"
        variables["FLOE_LAUNCH_TYPE"] = launch.type
        variables["FLOE_LAUNCH_CONTEXT"] = CommandLauncher.data(launch.context).flatMap { String(bytes: $0, encoding: .utf8) }
        variables["FLOE_FALLBACK_TEXT"] = launch.fallbackText
        variables[referencesVariable] = String(KeptRender.referenceVersion)
        variables[accessVariable] = recordsAccess ? nil : accessOff
        variables[developmentVariable] = isDevelopment ? "1" : nil
        variables[appearanceVariable] = isDark.map { $0 ? "dark" : "light" }
        return variables
    }

    /// Whether an extension is one being worked on in the checkout, and not one that was installed.
    static func isUnderDevelopment(_ folder: URL, developmentFolder: URL? = Paths.developmentExtensions) -> Bool {
        guard let developmentFolder else { return false }
        return folder.standardizedFileURL.path.hasPrefix(developmentFolder.standardizedFileURL.path + "/")
    }
}
