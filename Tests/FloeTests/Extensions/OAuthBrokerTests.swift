//
//  OAuthBrokerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// A sign-in waiting on the shared broker, registered without opening the browser.
private final nonisolated class Waiter: Sendable {
    private let answers = Mutex<[Result<String, any Error>]>([])

    init(_ extensionName: String, state: String) {
        OAuthBroker.shared.register(extensionName: extensionName, state: state) { [self] answer in
            answers.withLock { $0.append(answer) }
        }
    }

    /// Every answer so far: the callback address, or the name of the `OAuthError` case.
    var outcomes: [String] {
        answers.withLock { answers in
            answers.map { answer in
                switch answer {
                case let .success(callback): callback
                case let .failure(error): (error as? OAuthError).map { String(describing: $0) } ?? "\(error)"
                }
            }
        }
    }
}

/// The broker is shared, so every test signs in as an extension of its own and leaves nothing waiting.
nonisolated struct OAuthBrokerTests {
    private let broker = OAuthBroker.shared
    private let name = "floe-oauth-tests-\(UUID().uuidString)"
    /// The state alone says whose sign-in a redirect is, so each test has one of its own.
    private let state = "state-\(UUID().uuidString)"

    private func redirect(_ query: String, to address: String = "floe://oauth") throws -> URL {
        try #require(URL(string: "\(address)?\(query)"))
    }

    private func failure(of request: HostRequest) async -> String? {
        do {
            _ = try await broker.perform(request, extensionName: name, installation: URL(fileURLWithPath: "/tmp/\(name)"))
            return nil
        } catch {
            return (error as? OAuthError).map { String(describing: $0) }
        }
    }

    @Test func aRedirectWithTheMatchingStateAnswersTheSignInWithTheWholeAddress() throws {
        let waiter = Waiter(name, state: state)
        let callback = try redirect("code=abc&state=\(state)&package_name=\(name)")
        broker.complete(url: callback)
        #expect(waiter.outcomes == [callback.absoluteString])

        broker.complete(url: callback)
        #expect(waiter.outcomes.count == 1, "a sign-in is answered once")
    }

    /// Google's installed-app clients return to com.raycast:/oauth; Sourcegraph's OAuth app to raycast://oauth.
    @Test(arguments: ["raycast://oauth", "com.raycast:/oauth"])
    func aRedirectToRaycastsAppAddressesAnswersTheSignIn(address: String) throws {
        let waiter = Waiter(name, state: state)
        let callback = try redirect("package_name=Extension&code=abc&state=\(state)", to: address)
        broker.complete(url: callback)
        #expect(waiter.outcomes == [callback.absoluteString])
    }

    @Test func aRedirectThroughRaycastsPageIsMatchedByItsStateAlone() throws {
        let waiter = Waiter(name, state: state)
        let callback = try redirect("code=abc&package_name=Extension&state=\(state)")
        broker.complete(url: callback)
        #expect(waiter.outcomes == [callback.absoluteString], "Raycast's page names every extension Extension")
    }

    @Test func theNoticeAboutRaycastIsAskedUntilItIsAgreedToAndNeverAfter() async {
        let seen = Mutex(false)
        let answers = Mutex([false, true])
        let asked = Mutex<[String]>([])
        let notice = RaycastSignInNotice(
            seen: { seen.withLock { $0 } },
            markSeen: { seen.withLock { $0 = true } },
            asks: { provider in
                asked.withLock { $0.append(provider) }
                return answers.withLock { $0.removeFirst() }
            }
        )
        #expect(await notice.allows(provider: "Notion") == false)
        #expect(seen.withLock { $0 } == false, "a no is not remembered")
        #expect(await notice.allows(provider: "Notion"))
        #expect(await notice.allows(provider: "Linear"))
        #expect(asked.withLock { $0 } == ["Notion", "Notion"])
    }

    @Test func aSignInTheNoticeIsRefusedForNeverOpensTheBrowser() async {
        let refusing = OAuthBroker(notice: RaycastSignInNotice(seen: { false }, markSeen: {}, asks: { _ in false }))
        do {
            _ = try await refusing.perform(.oauthAuthorize(url: "https://example.com/auth", state: "s1", providerName: "Notion"), extensionName: name, installation: URL(fileURLWithPath: "/tmp/\(name)"))
            Issue.record("the sign-in went ahead")
        } catch {
            #expect((error as? OAuthError).map { String(describing: $0) } == "cancelled")
        }
    }

    @Test func aRedirectCarryingAnErrorIsHandedOnForTheHostToRead() throws {
        let waiter = Waiter(name, state: state)
        let callback = try redirect("error=access_denied&state=\(state)&package_name=\(name)")
        broker.complete(url: callback)
        #expect(waiter.outcomes == [callback.absoluteString])
    }

    @Test(arguments: [
        ("https://oauth", "code=abc&state=STATE&package_name=NAME"),
        ("floe://open", "code=abc&state=STATE&package_name=NAME"),
        ("raycast://extensions/x", "code=abc&state=STATE&package_name=NAME"),
        ("com.raycast:/other", "code=abc&state=STATE&package_name=NAME"),
        ("floe://oauth", "code=abc&package_name=NAME"),
        ("floe://oauth", "code=abc&state=other&package_name=NAME"),
    ])
    func aRedirectThatIsNotThisSignInsLeavesItWaiting(address: String, query: String) throws {
        let waiter = Waiter(name, state: state)
        try broker.complete(url: redirect(query.replacingOccurrences(of: "NAME", with: name).replacingOccurrences(of: "STATE", with: state), to: address))
        #expect(waiter.outcomes.isEmpty)

        broker.cancel(extensionName: name, state: state)
        #expect(waiter.outcomes == ["cancelled"], "it was still waiting")
    }

    @Test func aRedirectWithNoQueryLeavesTheSignInWaiting() throws {
        let waiter = Waiter(name, state: state)
        try broker.complete(url: #require(URL(string: "floe://oauth")))
        #expect(waiter.outcomes.isEmpty)
        broker.cancelAll(for: name)
    }

    @Test(arguments: ["s1", "s2"])
    func aNewerSignInFromTheSameExtensionReplacesTheOneWaiting(newerState: String) throws {
        let newerState = newerState == "s1" ? state : state + "-newer"
        let older = Waiter(name, state: state)
        let newer = Waiter(name, state: newerState)
        #expect(older.outcomes == ["replaced"])
        #expect(newer.outcomes.isEmpty)

        let callback = try redirect("code=abc&state=\(newerState)&package_name=\(name)")
        broker.complete(url: callback)
        #expect(older.outcomes == ["replaced"])
        #expect(newer.outcomes == [callback.absoluteString])
    }

    @Test func cancellingASignInFailsThatOneOnly() {
        let waiter = Waiter(name, state: state)
        broker.cancel(extensionName: name, state: "unknown")
        #expect(waiter.outcomes.isEmpty)

        broker.cancel(extensionName: name, state: state)
        broker.cancel(extensionName: name, state: state)
        #expect(waiter.outcomes == ["cancelled"])
    }

    @Test func aStoppingSessionFailsItsOwnSignInsAndNoOneElses() throws {
        let other = name + "-other"
        let mine = Waiter(name, state: state)
        let theirs = Waiter(other, state: state)
        broker.cancelAll(for: name)
        #expect(mine.outcomes == ["cancelled"])
        #expect(theirs.outcomes.isEmpty)

        let callback = try redirect("code=abc&state=\(state)&package_name=\(other)")
        broker.complete(url: callback)
        #expect(theirs.outcomes == [callback.absoluteString])
        #expect(mine.outcomes == ["cancelled"])
    }

    @Test(arguments: zip(
        [OAuthError.timedOut, .cancelled, .replaced, .unknownRequest, .invalidRedirect("The provider said no.")],
        [
            "Sign-in timed out.", "Sign-in was cancelled.", "Sign-in was replaced by a newer request.",
            "Floe can't answer that request.", "The provider said no.",
        ]
    ))
    func everySignInFailureSaysWhatHappened(error: OAuthError, message: String) {
        #expect(error.errorDescription == message)
        #expect(error.localizedDescription == message)
    }

    @Test(arguments: [HostRequest.askAI(prompt: "hello", model: nil), .selectedText, .selectedFinderItems, .clipboardRead(offset: 0)])
    func aRequestThatIsNotASignInIsRefused(request: HostRequest) async {
        #expect(await failure(of: request) == "unknownRequest")
    }

    @Test func aSignInWithNoUsableAddressFailsBeforeTheBrowserOpens() async {
        let request = HostRequest.oauthAuthorize(url: "", state: "s1", providerName: "Provider")
        #expect(await failure(of: request) == #"invalidRedirect("Missing or invalid param: url")"#)
    }
}

/// Token storage over a keychain in memory: an extension's tokens belong to the folder it was installed in.
struct OAuthTokenStorageTests {
    private let keychain = MemoryKeychain()
    private let broker: OAuthBroker
    private let installed = URL(fileURLWithPath: "/Users/someone/Library/Application Support/Floe/Extensions/github")
    private let elsewhere = URL(fileURLWithPath: "/Users/someone/Library/Application Support/Floe/Extensions/aaa-other")
    private let tokens = #"{"accessToken":"secret","updatedAt":"2026-10-29T00:00:00Z"}"#

    init() {
        broker = OAuthBroker(vault: SecretVault(keychain: keychain, defaults: ScratchDefaults().defaults, isEntitled: { false }))
    }

    private func read(from installation: URL) async throws -> String? {
        let answer = try await broker.perform(.oauthGetTokens(providerId: "github"), extensionName: "github", installation: installation)
        return (answer as? [String: Any])?["accessToken"] as? String
    }

    @Test func anExtensionThatNeverSignedInHasNoTokens() async throws {
        let answer = try await broker.perform(.oauthGetTokens(providerId: "none"), extensionName: "github", installation: installed)
        #expect(answer is NSNull)
        #expect(broker.tokens(extensionName: "github", providerId: "none", installation: installed) == nil)
    }

    @Test func anotherPackageWithTheSameNameCannotReadTheTokens() async throws {
        _ = try await broker.perform(.oauthSetTokens(providerId: "github", tokens: tokens), extensionName: "github", installation: installed)
        #expect(try await read(from: elsewhere) == nil)
        #expect(try await read(from: installed) == "secret")
    }

    @Test func anotherPackageWithTheSameNameCannotRemoveTheTokens() async throws {
        _ = try await broker.perform(.oauthSetTokens(providerId: "github", tokens: tokens), extensionName: "github", installation: installed)
        _ = try await broker.perform(.oauthRemoveTokens(providerId: "github"), extensionName: "github", installation: elsewhere)
        #expect(try await read(from: installed) == "secret")

        _ = try await broker.perform(.oauthRemoveTokens(providerId: "github"), extensionName: "github", installation: installed)
        #expect(try await read(from: installed) == nil)
    }

    @Test func anUpdateInTheSameFolderKeepsTheTokens() async throws {
        _ = try await broker.perform(.oauthSetTokens(providerId: "github", tokens: tokens), extensionName: "github", installation: installed)
        let sameFolder = installed.appendingPathComponent("assets").appendingPathComponent("..")
        #expect(try await read(from: sameFolder) == "secret")
    }

    @Test func aSignInInTheOtherFolderStartsItsOwnTokensAndHandsNothingOver() async throws {
        _ = try await broker.perform(.oauthSetTokens(providerId: "github", tokens: tokens), extensionName: "github", installation: installed)
        _ = try await broker.perform(
            .oauthSetTokens(providerId: "github", tokens: #"{"accessToken":"theirs"}"#), extensionName: "github", installation: elsewhere
        )
        #expect(try await read(from: elsewhere) == "theirs")
        #expect(try await read(from: installed) == nil, "tokens another folder saved are not handed to this one either")
    }

    @Test func tokensSavedBeforeTheyHadAFolderGoToTheFirstThatAsks() async throws {
        keychain.write(tokens, service: SecretVault.service, account: "github/oauth/github", synchronizable: false)
        #expect(try await read(from: installed) == "secret")
        #expect(try await read(from: elsewhere) == nil)
        #expect(try await read(from: installed) == "secret")
    }
}
