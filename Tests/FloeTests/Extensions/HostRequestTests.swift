//
//  HostRequestTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct HostRequestTests {
    @Test func anApplicationCarriesItsNameItsPathAndItsBundleIdentifier() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-host-request-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("Helium.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "net.imput.helium"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        #expect(HostRequest.application(at: app) == ["name": "Helium", "path": app.path, "bundleId": "net.imput.helium"], "what getDefaultApplication answers with")
        #expect(HostRequest.application(at: app, name: "Helium Browser")["name"] == "Helium Browser", "the frontmost app goes by the name it shows")
        let bare = folder.appendingPathComponent("Script.app")
        #expect(HostRequest.application(at: bare) == ["name": "Script", "path": bare.path], "no bundle, no identifier")
    }

    private let claude = URL(fileURLWithPath: "/tools/claude")
    private let codex = URL(fileURLWithPath: "/tools/codex")

    private func installed(_ names: String...) -> (String) -> URL? {
        { name in names.contains(name) ? URL(fileURLWithPath: "/tools/\(name)") : nil }
    }

    @Test func tokensToStoreAreCarriedAsTheSameTextWhateverTheirOrder() throws {
        let first = try #require(HostRequest(method: "oauth.setTokens", params: ["providerId": "github", "tokens": ["accessToken": "a", "scope": "repo"]]))
        let second = try #require(HostRequest(method: "oauth.setTokens", params: ["providerId": "github", "tokens": ["scope": "repo", "accessToken": "a"]]))
        #expect(first == second)
        #expect(first == .oauthSetTokens(providerId: "github", tokens: #"{"accessToken":"a","scope":"repo"}"#))
        #expect(HostRequest(method: "oauth.setTokens", params: ["providerId": "github"]) == nil)
    }

    @Test func anAskCarriesItsPromptAndModel() {
        #expect(HostRequest(method: "ai.ask", params: ["prompt": "why?", "model": "Anthropic_Claude_Sonnet"]) == .askAI(prompt: "why?", model: "Anthropic_Claude_Sonnet"))
        #expect(HostRequest(method: "ai.ask", params: ["prompt": "why?"]) == .askAI(prompt: "why?", model: nil))
    }

    @Test func anUnknownMethodOrAMissingPromptIsNoRequest() {
        #expect(HostRequest(method: "ai.ask", params: [:]) == nil)
        #expect(HostRequest(method: "oauth.authorize", params: ["prompt": "why?"]) == nil)
    }

    @Test func environmentQuestionsAreRequests() {
        #expect(HostRequest(method: "environment.frontmostApplication", params: [:]) == .frontmostApplication)
        #expect(HostRequest(method: "environment.getDefaultApplication", params: ["path": "/tmp/notes.txt"]) == .defaultApplication(path: "/tmp/notes.txt"))
        #expect(HostRequest(method: "environment.getDefaultApplication", params: [:]) == nil)
    }

    @Test func claudeAnswersWhenItIsInstalled() {
        #expect(AIEngine.resolve(model: nil, which: installed("claude", "codex")) == .claude(executable: claude, model: nil))
        #expect(AIEngine.resolve(model: "Anthropic_Claude_Opus", which: installed("claude")) == .claude(executable: claude, model: "opus"))
    }

    @Test func codexAnswersWhenItIsAllThereIsOrAnOpenAIModelIsAsked() {
        #expect(AIEngine.resolve(model: nil, which: installed("codex")) == .codex(executable: codex, model: nil))
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", which: installed("claude", "codex")) == .codex(executable: codex, model: nil))
        #expect(AIEngine.resolve(model: "openai-gpt-4o", which: installed("claude")) == .claude(executable: claude, model: nil))
    }

    @Test func nothingAnswersWithoutATool() {
        #expect(AIEngine.resolve(model: nil, which: installed()) == nil)
        for tool in AITool.allCases {
            #expect(AIEngine.missingMessage.contains(tool.command))
        }
    }

    @Test(arguments: [
        ("Anthropic_Claude_Sonnet", "sonnet"),
        ("anthropic-claude-haiku", "haiku"),
        ("Anthropic_Claude_Opus", "opus"),
    ])
    func raycastsModelNamesMapToClaudesAliases(requested: String, alias: String) {
        #expect(AIEngine.claudeModel(for: requested) == alias)
    }

    @Test func otherModelNamesLeaveTheChoiceToTheEngine() {
        #expect(AIEngine.claudeModel(for: nil) == nil)
        #expect(AIEngine.claudeModel(for: "Perplexity_Sonar") == nil)
    }

    // MARK: The API

    @Test func theChatAddressSitsUnderTheBaseAddress() {
        #expect(AIEndpoint.chatURL(baseURL: "https://api.openai.com/v1")?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: " http://localhost:11434/v1// ")?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: "https://api.z.ai/api/paas/v4/chat/completions")?.absoluteString == "https://api.z.ai/api/paas/v4/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: "")?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test(arguments: ["api.openai.com/v1", "ftp://example.com", "https://", "not a url"])
    func anAddressThatIsNotAWebAddressIsRefused(address: String) {
        #expect(AIEndpoint.chatURL(baseURL: address) == nil)
    }

    @Test func anEndpointNeedsItsAddressModelAndKey() {
        let endpoint = AIEndpoint(baseURL: "https://api.test/v1", model: " small ", apiKey: " key-123\n")
        #expect(endpoint?.chatURL.absoluteString == "https://api.test/v1/chat/completions")
        #expect(endpoint?.model == "small")
        #expect(endpoint?.apiKey == "key-123")
        #expect(AIEndpoint(baseURL: "https://api.test/v1", model: "", apiKey: "key") == nil)
        #expect(AIEndpoint(baseURL: "https://api.test/v1", model: "small", apiKey: nil) == nil)
        #expect(AIEndpoint(baseURL: "nonsense", model: "small", apiKey: "key") == nil)
    }

    @Test func aCompleteSetupHasNoProblem() {
        #expect(AIEndpoint.problem(baseURL: "https://api.test/v1", model: "small", apiKey: "key") == nil)
        #expect(AIEndpoint.problem(baseURL: "", model: "small", apiKey: "key") == nil)
    }

    @Test func anIncompleteSetupSaysWhatItStillNeeds() {
        #expect(AIEndpoint.problem(baseURL: "https://api.test/v1", model: " ", apiKey: "key") == "AI can't answer yet. It needs a model.")
        #expect(AIEndpoint.problem(baseURL: "https://api.test/v1", model: "", apiKey: nil) == "AI can't answer yet. It needs a model and an API key.")
        #expect(AIEndpoint.problem(baseURL: "nonsense", model: "", apiKey: "") == "AI can't answer yet. It needs an address that starts with http:// or https://, a model and an API key.")
    }

    @Test func aServerOnThisMacNeedsNoKey() {
        let local = AIEndpoint(baseURL: "http://localhost:11434/v1", model: "llama3.2", apiKey: nil)
        #expect(local?.chatURL.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(local?.apiKey.isEmpty == true)
        #expect(AIEndpoint.problem(baseURL: "http://127.0.0.1:1234/v1", model: "qwen", apiKey: "") == nil)
        #expect(AIEndpoint.problem(baseURL: "http://localhost:11434/v1", model: "", apiKey: nil) == "AI can't answer yet. It needs a model.")
        #expect(AIEndpoint.needsKey(URL(string: "https://openrouter.ai/api/v1/chat/completions")))
        #expect(AIEndpoint.needsKey(nil), "an address that is not one still asks for everything")
    }

    @Test func aRequestWithoutAKeyCarriesNoAuthorizationHeader() throws {
        let url = try #require(URL(string: "http://localhost:11434/v1/chat/completions"))
        let keyless = ChatCompletionStream.request(chatURL: url, apiKey: "", model: "llama3.2", prompt: "hi")
        #expect(keyless.value(forHTTPHeaderField: "Authorization") == nil)
        let keyed = ChatCompletionStream.request(chatURL: url, apiKey: "key-123", model: "llama3.2", prompt: "hi")
        #expect(keyed.value(forHTTPHeaderField: "Authorization") == "Bearer key-123")
    }

    @Test func theServicePickerFollowsTheAddressThatIsStored() {
        #expect(AIService.matching("") == .openAI, "an empty address is OpenAI's")
        #expect(AIService.matching("https://api.openai.com/v1/") == .openAI)
        #expect(AIService.matching("http://localhost:11434/v1") == .ollama)
        #expect(AIService.matching("http://localhost:1234/v1/chat/completions") == .lmStudio)
        #expect(AIService.matching("https://openrouter.ai/api/v1") == .openRouter)
        #expect(AIService.matching("https://api.z.ai/api/paas/v4") == .zai)
        #expect(AIService.matching("https://api.z.ai/api/coding/paas/v4") == .other, "the Coding Plan's address is not the preset")
        #expect(AIService.matching("nonsense") == .other)
        #expect(AIService.allCases.filter { $0.baseURL == nil } == [.other])
    }

    @Test func appleIntelligenceIsAChoiceThatNeverReadsTheKey() {
        let choice = AIAnswer.choice(source: .appleIntelligence, baseURL: "", model: "") {
            Issue.record("the Keychain was read for the on-device model")
            return "key"
        }
        #expect(choice == .appleIntelligence)
    }

    @Test func onlyWhatIsNewInAnAnswerIsPassedOn() {
        #expect(AppleIntelligence.addition(from: "", to: "po") == "po")
        #expect(AppleIntelligence.addition(from: "po", to: "pong") == "ng")
        #expect(AppleIntelligence.addition(from: "pong", to: "pong").isEmpty)
        #expect(AppleIntelligence.addition(from: "ping", to: "pong") == "pong", "a rewritten answer is sent whole")
    }

    @Test func theToolsChoiceNeverReadsTheKey() {
        let choice = AIAnswer.choice(source: .tools, baseURL: "https://api.test/v1", model: "small") {
            Issue.record("the Keychain was read for the tools")
            return "key"
        }
        #expect(choice == .tools)
    }

    @Test func theAPIChoiceCarriesItsEndpointOrNothingWhenIncomplete() {
        let complete = AIAnswer.choice(source: .api, baseURL: "https://api.test/v1", model: "small") { "key" }
        #expect(complete == .api(AIEndpoint(baseURL: "https://api.test/v1", model: "small", apiKey: "key")))
        #expect(AIAnswer.choice(source: .api, baseURL: "https://api.test/v1", model: "small") { nil } == .api(nil))
        #expect(AIAnswer.incompleteMessage.contains("Settings"))
    }

    @Test func signingInCarriesThePageTheStateAndTheProvider() {
        let params = ["url": "https://github.com/login/oauth/authorize", "state": "s-1", "providerName": "GitHub"]
        #expect(HostRequest(method: "oauth.authorize", params: params) == .oauthAuthorize(url: "https://github.com/login/oauth/authorize", state: "s-1", providerName: "GitHub"))
        for missing in ["url", "state", "providerName"] {
            #expect(HostRequest(method: "oauth.authorize", params: params.filter { $0.key != missing }) == nil, "\(missing)")
        }
    }

    @Test func readingAndRemovingTokensNameTheirProvider() {
        #expect(HostRequest(method: "oauth.getTokens", params: ["providerId": "github"]) == .oauthGetTokens(providerId: "github"))
        #expect(HostRequest(method: "oauth.removeTokens", params: ["providerId": "github"]) == .oauthRemoveTokens(providerId: "github"))
        #expect(HostRequest(method: "oauth.getTokens", params: [:]) == nil)
        #expect(HostRequest(method: "oauth.removeTokens", params: ["providerId": 7]) == nil)
        #expect(HostRequest(method: "oauth.setTokens", params: ["tokens": ["accessToken": "a"]]) == nil)
        #expect(HostRequest(method: "oauth.setTokens", params: ["providerId": "github", "tokens": "a"]) == nil)
    }

    @Test(arguments: [("selectedText", HostRequest.selectedText), ("selectedFinderItems", .selectedFinderItems), ("clipboard.read", .clipboardRead)])
    func aRequestWithoutParametersIsReadFromItsMethodAlone(method: String, request: HostRequest) {
        #expect(HostRequest(method: method, params: [:]) == request)
        #expect(HostRequest(method: method, params: ["extra": true]) == request)
    }

    @Test(arguments: ["", "ai.Ask", "clipboard.write", "oauth"])
    func aMethodTheAppDoesNotKnowIsNoRequest(method: String) {
        #expect(HostRequest(method: method, params: ["prompt": "why?", "providerId": "github"]) == nil)
    }

    @Test(arguments: [
        (HostRequest.oauthAuthorize(url: "https://example.com", state: "s", providerName: "Example"), true),
        (.oauthGetTokens(providerId: "github"), true),
        (.oauthSetTokens(providerId: "github", tokens: "{}"), true),
        (.oauthRemoveTokens(providerId: "github"), true),
        (.askAI(prompt: "why?", model: nil), false),
        (.selectedText, false),
        (.selectedFinderItems, false),
        (.clipboardRead, false),
    ])
    func onlySignInRequestsGoToTheOAuthBroker(request: HostRequest, isOAuth: Bool) {
        #expect(request.isOAuth == isOAuth)
    }

    @Test(arguments: [
        HostRequest.oauthAuthorize(url: "https://example.com", state: "s", providerName: "Example"),
        .oauthGetTokens(providerId: "github"),
        .oauthSetTokens(providerId: "github", tokens: "{}"),
        .oauthRemoveTokens(providerId: "github"),
    ])
    func aSignInRequestIsNotAnsweredOutsideTheBroker(request: HostRequest) async {
        let failure = await #expect(throws: OAuthError.self) {
            try await HostRequest.answer(request) { _ in Issue.record("nothing is streamed for a sign-in request") }
        }
        guard case .unknownRequest = failure else {
            Issue.record("\(String(describing: failure))")
            return
        }
    }

    @Test(arguments: [
        (AIService.openAI, "https://api.openai.com/v1"),
        (.openRouter, "https://openrouter.ai/api/v1"),
        (.zai, "https://api.z.ai/api/paas/v4"),
        (.ollama, "http://localhost:11434/v1"),
        (.lmStudio, "http://localhost:1234/v1"),
    ])
    func everyPresetServiceIsFoundAgainFromItsOwnAddress(service: AIService, address: String) {
        #expect(service.baseURL == address)
        #expect(AIService.matching(address) == service)
        #expect(AIService.matching("  \(address)/chat/completions/ ") == service)
    }

    @Test func servicesAreNamedAndIdentifiedForThePicker() {
        #expect(AIService.allCases.map(\.id) == ["openAI", "openRouter", "zai", "ollama", "lmStudio", "other"])
        #expect(AIService.allCases.map(\.title) == ["OpenAI", "OpenRouter", "Z.ai", "Ollama, on this Mac", "LM Studio, on this Mac", "Another address"])
        #expect(AIService.other.baseURL == nil)
    }

    @Test func anAddressOnAnotherPortOrSchemeIsNotThePreset() {
        #expect(AIService.matching("http://localhost:8080/v1") == .other)
        #expect(AIService.matching("http://api.openai.com/v1") == .other)
        #expect(AIService.matching("https://openrouter.ai/api/v2") == .other)
    }

    @Test(arguments: ["http://localhost:1234/v1", "http://LOCALHOST/v1", "http://127.0.0.1:11434", "http://[::1]:8080/v1"])
    func anAddressOnThisMacNeedsNoKey(address: String) {
        #expect(AIEndpoint.isOnThisMac(URL(string: address)))
        #expect(!AIEndpoint.needsKey(URL(string: address)))
    }

    @Test(arguments: ["https://api.openai.com/v1", "http://192.168.1.20:11434/v1", "http://localhost.example.com/v1", "file:///tmp/model"])
    func anAddressElsewhereNeedsAKey(address: String) {
        #expect(!AIEndpoint.isOnThisMac(URL(string: address)))
        #expect(AIEndpoint.needsKey(URL(string: address)))
    }

    @Test func theChatAddressKeepsItsPortPathAndCase() {
        #expect(AIEndpoint.chatURL(baseURL: "HTTPS://Example.com:8443/proxy/v1///")?.absoluteString == "HTTPS://Example.com:8443/proxy/v1/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: "https://api.test/v1/chat/completions/")?.absoluteString == "https://api.test/v1/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: " \n")?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: "https://api.test")?.absoluteString == "https://api.test/chat/completions")
    }

    @Test(arguments: [
        ("nonsense", "small", "key", "AI can't answer yet. It needs an address that starts with http:// or https://."),
        ("https://api.test/v1", "small", " ", "AI can't answer yet. It needs an API key."),
        ("ftp://api.test/v1", "\n", "key", "AI can't answer yet. It needs an address that starts with http:// or https:// and a model."),
        ("api.test/v1", "small", "", "AI can't answer yet. It needs an address that starts with http:// or https:// and an API key."),
    ])
    func eachMissingPartOfTheSetupHasItsOwnSentence(address: String, model: String, key: String, sentence: String) {
        #expect(AIEndpoint.problem(baseURL: address, model: model, apiKey: key) == sentence)
        #expect(AIEndpoint(baseURL: address, model: model, apiKey: key) == nil)
    }

    @MainActor @Test func theChoiceInSettingsIsReadWithoutTheKeyUnlessTheAPIIsChosen() throws {
        let scratch = try ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults, savesAfterEdits: false)
        #expect(AIAnswer.configured(settings) == .tools)
        settings.aiSource = .appleIntelligence
        #expect(AIAnswer.configured(settings) == .appleIntelligence)
    }
}
