//
//  LentSignInTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

struct LentSignInTests {
    /// What the stand-ins were asked and told, which happens off the main actor.
    private final class Book: Sendable {
        let allowed = Mutex<Set<String>>([])
        let questions = Mutex<[String]>([])
        let answer = Mutex(true)
        let token = Mutex<String?>("gho_token")
        let scopes = Mutex<[String]>(["gist", "repo"])
        let scopesRead = Mutex(0)
        let named = Mutex<[[String]]>([])
    }

    private func lender(_ book: Book) -> SignInLender {
        SignInLender(
            token: { _ in book.token.withLock { $0 } },
            scopes: { _ in
                book.scopesRead.withLock { $0 += 1 }
                return book.scopes.withLock { $0 }
            },
            asks: { title, provider, scopes in
                book.questions.withLock { $0.append("\(title) → \(provider.name)") }
                book.named.withLock { $0.append(scopes) }
                return book.answer.withLock { $0 }
            },
            isAllowed: { key in book.allowed.withLock { $0.contains(key) } },
            allow: { key in book.allowed.withLock { _ = $0.insert(key) } },
            takeBack: { key in book.allowed.withLock { _ = $0.remove(key) } }
        )
    }

    @Test func onlyGitHubIsLentByItsIdOrItsName() {
        #expect(LentProvider(providerId: "github") == .github)
        #expect(LentProvider(providerId: " GitHub ") == .github)
        #expect(LentProvider(providerId: "github-enterprise") == nil)
        #expect(LentProvider(providerId: "google") == nil)
        #expect(LentProvider.github.key(for: "github-stars") == "github-stars/github")
    }

    @Test func theUserIsAskedOnceForAnExtensionAndThenItIsLentTheToken() async {
        let book = Book()
        let lender = lender(book)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let first = await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub", now: now)
        #expect(first?["accessToken"] as? String == "gho_token")
        #expect(first?["updatedAt"] as? String == now.ISO8601Format())
        #expect(first?["expiresIn"] == nil, "it does not run out as far as the extension knows")
        #expect(book.questions.withLock { $0 } == ["GitHub → GitHub"])
        #expect(book.allowed.withLock { $0 } == ["github/github"])

        let second = await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub", now: now)
        #expect(second?["accessToken"] as? String == "gho_token")
        #expect(book.questions.withLock { $0.count } == 1, "allowed once is allowed")

        _ = await lender.tokens(for: .github, extensionName: "gitpod", extensionTitle: "Gitpod", now: now)
        #expect(book.questions.withLock { $0 } == ["GitHub → GitHub", "Gitpod → GitHub"], "each extension is asked for by itself")
    }

    @Test func aNoIsNotAskedAgainUntilFloeStartsAgainAndLendsNothing() async {
        let book = Book()
        book.answer.withLock { $0 = false }
        let lender = lender(book)
        #expect(await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub") == nil)
        #expect(await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub") == nil)
        #expect(book.questions.withLock { $0.count } == 1)
        #expect(book.allowed.withLock { $0 }.isEmpty)

        book.answer.withLock { $0 = true }
        #expect(await self.lender(book).tokens(for: .github, extensionName: "github", extensionTitle: "GitHub") != nil, "a new start asks again")
    }

    @Test func withNoSignInOnThisMacNothingIsAskedOrLent() async {
        let book = Book()
        book.token.withLock { $0 = nil }
        #expect(await lender(book).tokens(for: .github, extensionName: "github", extensionTitle: "GitHub") == nil)
        #expect(book.questions.withLock { $0 }.isEmpty, "there is nothing to allow")
    }

    @Test func theQuestionNamesWhatTheSignInMayAndTheScopesAreReadOnlyToAsk() async {
        let book = Book()
        let lender = lender(book)
        _ = await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub")
        #expect(book.named.withLock { $0 } == [["gist", "repo"]])
        _ = await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub")
        #expect(book.scopesRead.withLock { $0 } == 1, "allowed already: nothing to ask, so nothing to read")

        book.scopes.withLock { $0 = [] }
        _ = await lender.tokens(for: .github, extensionName: "gitpod", extensionTitle: "Gitpod")
        #expect(book.named.withLock { $0.last } == [], "scopes that cannot be read do not stop the question")

        book.token.withLock { $0 = nil }
        _ = await lender.tokens(for: .github, extensionName: "stars", extensionTitle: "Stars")
        #expect(book.scopesRead.withLock { $0 } == 2, "with no sign-in there is nothing to describe")
    }

    @Test func theQuestionListsTheScopesOrSpeaksInGeneralWithoutThem() {
        let named = SignInLender.explanation(scopes: ["admin:org", "copilot", "gist", "project", "repo", "workflow"])
        #expect(named.contains("This sign-in may: admin:org, copilot, gist, project, repo, workflow."))
        #expect(named.hasPrefix("Floe can lend this extension the sign-in of the GitHub CLI on this Mac."))
        #expect(named.hasSuffix("You can take this back on the extension’s page in Settings."))
        let general = SignInLender.explanation(scopes: [])
        #expect(!general.contains("This sign-in may"))
        #expect(general.contains("The extension can then do everything that sign-in may"))
    }

    @Test func theScopesAreReadFromWhatTheCLIPrints() {
        let status = """
        github.com
          ✓ Logged in to github.com account rene (keyring)
          - Active account: true
          - Git operations protocol: https
          - Token: gho_************************************
          - Token scopes: 'admin:org', 'copilot', 'gist', 'project', 'repo', 'workflow'
        """
        #expect(SignInLender.scopes(inStatus: status) == ["admin:org", "copilot", "gist", "project", "repo", "workflow"])
        #expect(SignInLender.scopes(inStatus: "- Token scopes: 'read:org'") == ["read:org"])
        #expect(SignInLender.scopes(inStatus: "\n" + status) == SignInLender.scopes(inStatus: status), "standard output was empty and it came on standard error")
    }

    @Test(arguments: [
        "  - Token scopes: none",
        "  - Token scopes: ",
        "  - Token scopes: admin:org, repo",
        "  - Token scopes: 'repo",
        "  - Token scopes: '', 'two words', '<b>'",
        "github.com\n  ✓ Logged in to github.com account rene (keyring)\n  - Token: gho_****",
        "You are not logged into any GitHub hosts. To log in, run: gh auth login",
        "",
    ])
    func noScopesAMalformedLineOrNoLineReadsAsNone(status: String) {
        #expect(SignInLender.scopes(inStatus: status) == [])
    }

    @Test func withSeveralAccountsTheScopesAreTheActiveOnes() {
        let status = """
        github.com
          ✓ Logged in to github.com account work (keyring)
          - Active account: false
          - Token scopes: 'admin:org', 'repo'

          ✓ Logged in to github.com account rene (keyring)
          - Active account: true
          - Token scopes: 'gist'
        """
        #expect(SignInLender.scopes(inStatus: status) == ["gist"])
    }

    @Test func signingOutTakesTheSignInBack() async {
        let book = Book()
        let lender = lender(book)
        _ = await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub")
        await lender.signOut(of: .github, extensionName: "github")
        #expect(book.allowed.withLock { $0 }.isEmpty)
        _ = await lender.tokens(for: .github, extensionName: "github", extensionTitle: "GitHub")
        #expect(book.questions.withLock { $0.count } == 2, "and using it again means asking again")
    }

    @Test func aRequestForGitHubsTokensIsAnsweredByTheLenderAndAnyOtherIsNot() async {
        let book = Book()
        let lender = lender(book)
        let lent = await OAuthBroker.lent(.oauthGetTokens(providerId: "github"), extensionName: "github", extensionTitle: "GitHub", lender: lender) as? [String: Any]
        #expect(lent?["accessToken"] as? String == "gho_token")
        #expect(await OAuthBroker.lent(.oauthGetTokens(providerId: "google"), extensionName: "drive", extensionTitle: "Drive", lender: lender) == nil)
        #expect(await OAuthBroker.lent(.oauthSetTokens(providerId: "github", tokens: "{}"), extensionName: "github", extensionTitle: "GitHub", lender: lender) == nil)

        #expect(await OAuthBroker.lent(.oauthRemoveTokens(providerId: "GitHub"), extensionName: "github", extensionTitle: "GitHub", lender: lender) is NSNull)
        #expect(book.allowed.withLock { $0 }.isEmpty, "removing its tokens is the extension signing out")

        #expect(HostRequest.oauthGetTokens(providerId: "x").asksOnlyForTokens)
        #expect(HostRequest.oauthRemoveTokens(providerId: "x").asksOnlyForTokens)
        #expect(!HostRequest.oauthSetTokens(providerId: "x", tokens: "").asksOnlyForTokens)
    }

    @MainActor @Test func whoIsLentASignInIsKeptInSettings() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-lent-tests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.lentSignIns.isEmpty)
        settings.lentSignIns.insert(LentProvider.github.key(for: "github"))
        settings.save()
        #expect(AppSettings(defaults: defaults).lentSignIns == ["github/github"])
    }
}
