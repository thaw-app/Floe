//
//  ThawAppearanceTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing

/// Thaw's answers, as Thaw writes them. The first is the example in Thaw's docs/URI_SCHEMES.md, copied
/// as it stands. Thaw's SharedAppearanceTests build their payloads from configurations and hold no JSON,
/// so the rest are those configurations written out the way Thaw's encoder does: nil fields left out.
private nonisolated enum ThawFixture {
    static let documented = """
    {"requestId":"5","operation":"get-appearance","status":"success",
     "data":{"version":1,"colorScheme":"dark","shape":"full","hasRoundedShape":true,"hasShadow":true,
      "border":{"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":1,"style":"solid"},
      "tint":{"kind":"solid","opacity":0.2,"color":{"red":0,"green":0,"blue":0,"alpha":1}},
      "background":{"kind":"none","opacity":1}}}
    """

    /// "A solid tint carries its color in sRGB and no gradient or glass fields".
    static let solidTint = """
    {"kind":"solid","opacity":0.4,"color":{"red":1,"green":0.5,"blue":0,"alpha":1}}
    """

    /// "A gradient fill carries its stops in order".
    static let gradient = """
    {"kind":"gradient","opacity":1,"stops":[
      {"color":{"red":1,"green":0,"blue":0,"alpha":1},"location":0},
      {"color":{"red":0,"green":0,"blue":1,"alpha":1},"location":1}]}
    """

    /// "Glass names its style, and keeps its color only when colored".
    static let clearGlass = """
    {"kind":"glass","opacity":1,"glassStyle":"clear","glassIsColored":false}
    """

    static let coloredGlass = """
    {"kind":"glass","opacity":0.5,"glassStyle":"liquid","glassIsColored":true,"color":{"red":0.2,"green":0.4,"blue":0.6,"alpha":1}}
    """

    static let none = """
    {"kind":"none","opacity":1}
    """

    static let adaptive = """
    {"kind":"adaptive","opacity":0.6}
    """

    static let adaptiveGradient = """
    {"kind":"adaptiveGradient","opacity":0.6}
    """

    /// "A border that is off is left out", and the dashed one it turns on.
    static let dashedBorder = """
    {"color":{"red":1,"green":1,"blue":1,"alpha":0.5},"width":2,"style":"dashed"}
    """

    /// "The payload names its version, scheme and shape".
    static func payload(
        version: Int = 1,
        scheme: String = "dark",
        tint: String = none,
        background: String = none,
        border: String? = nil,
        hasShadow: Bool = false
    ) -> String {
        let borderField = border.map { "\"border\":\($0)," } ?? ""
        return """
        {"version":\(version),"colorScheme":"\(scheme)","shape":"notch","hasRoundedShape":true,"hasShadow":\(hasShadow),\
        \(borderField)"tint":\(tint),"background":\(background)}
        """
    }

    static func envelope(requestId: String, status: String = "success", operation: String = "get-appearance", data: String = payload()) -> String {
        """
        {"requestId":"\(requestId)","operation":"\(operation)","status":"\(status)","data":\(data)}
        """
    }

    /// The link Thaw opens: the callback with the answer appended as `data`.
    static func callback(_ json: String, host: String = "thaw-appearance") throws -> URL {
        var components = try #require(URLComponents(string: "floe://\(host)"))
        components.queryItems = [URLQueryItem(name: "data", value: json)]
        return try #require(components.url)
    }

    @MainActor
    static func appearance(_ payload: String) throws -> ThawAppearance {
        try ThawAppearanceResponse.appearance(in: Data(envelope(requestId: "1", data: payload).utf8))
    }
}

/// The launcher's own look in these tests: nothing in it matches what Thaw sends.
private let own = LauncherLook(
    glass: LauncherGlass(style: .dynamic, color: StoredColor(Color(red: 0.9, green: 0.1, blue: 0.1))),
    tint: LauncherTint(kind: .gradient, opacity: 0.7),
    border: LauncherBorder(width: 3),
    hasShadow: false
)

struct ThawAppearanceDecodingTests {
    @Test func theDocumentedExampleDecodes() throws {
        let body = Data(ThawFixture.documented.utf8)
        #expect(ThawAppearanceResponse.header(of: body) == .init(requestId: "5", operation: "get-appearance", status: "success"))
        let appearance = try ThawAppearanceResponse.appearance(in: body)
        #expect(appearance.version == 1)
        #expect(appearance.colorScheme == .dark)
        #expect(appearance.hasShadow)
        #expect(appearance.border == .init(color: .init(red: 0, green: 0, blue: 0, alpha: 1), width: 1))
        #expect(appearance.tint == .init(kind: "solid", opacity: 0.2, color: .init(red: 0, green: 0, blue: 0, alpha: 1)))
        #expect(appearance.background == .init(kind: "none", opacity: 1))
    }

    @Test(arguments: [
        ThawFixture.solidTint, ThawFixture.gradient, ThawFixture.clearGlass, ThawFixture.coloredGlass,
        ThawFixture.none, ThawFixture.adaptive, ThawFixture.adaptiveGradient,
    ])
    func everyKindOfFillDecodesAsTheTintAndAsTheBackground(fill: String) throws {
        let appearance = try ThawFixture.appearance(ThawFixture.payload(scheme: "light", tint: fill, background: fill))
        #expect(appearance.colorScheme == .light)
        #expect(appearance.tint == appearance.background)
        #expect(fill.contains("\"kind\":\"\(appearance.tint.kind)\""))
    }

    @Test func theFieldsOfEachKindComeThrough() throws {
        let solid = try ThawFixture.appearance(ThawFixture.payload(tint: ThawFixture.solidTint)).tint
        #expect(solid.color == .init(red: 1, green: 0.5, blue: 0, alpha: 1))
        #expect(solid.opacity == 0.4)
        #expect(solid.stops == nil)
        #expect(solid.glassStyle == nil)
        let gradient = try ThawFixture.appearance(ThawFixture.payload(background: ThawFixture.gradient)).background
        #expect(gradient.stops?.map(\.location) == [0, 1])
        #expect(gradient.stops?.first?.color.red == 1)
        #expect(gradient.color == nil)
        let glass = try ThawFixture.appearance(ThawFixture.payload(background: ThawFixture.clearGlass)).background
        #expect(glass.glassStyle == "clear")
        #expect(glass.glassIsColored == false)
        #expect(glass.color == nil)
    }

    @Test func aBorderThatIsOffIsAbsentAndOneThatIsOnHasItsWidth() throws {
        #expect(try ThawFixture.appearance(ThawFixture.payload()).border == nil)
        let border = try ThawFixture.appearance(ThawFixture.payload(border: ThawFixture.dashedBorder)).border
        #expect(border == .init(color: .init(red: 1, green: 1, blue: 1, alpha: 0.5), width: 2))
    }

    @Test func aVersionFloeDoesNotKnowIsRejected() {
        let body = Data(ThawFixture.envelope(requestId: "1", data: ThawFixture.payload(version: 2)).utf8)
        #expect(throws: ThawAppearanceResponse.Rejection.unsupportedVersion) {
            try ThawAppearanceResponse.appearance(in: body)
        }
    }

    @Test func aFailedStatusIsRejected() {
        let failed = """
        {"requestId":"1","operation":"get-appearance","status":"error","error":"invalidRequest","details":"No"}
        """
        #expect(throws: ThawAppearanceResponse.Rejection.failed) {
            try ThawAppearanceResponse.appearance(in: Data(failed.utf8))
        }
        // An acknowledgement is what a broadcast gets, and carries no look.
        #expect(throws: ThawAppearanceResponse.Rejection.failed) {
            try ThawAppearanceResponse.appearance(in: Data(ThawFixture.envelope(requestId: "1", status: "ack").utf8))
        }
    }

    @Test(arguments: [
        "",
        "not json",
        "[]",
        "{\"requestId\":\"1\",\"operation\":\"get-appearance\",\"status\":\"success\"}",
        "{\"requestId\":\"1\",\"operation\":\"get-appearance\",\"status\":\"success\",\"data\":{}}",
        "{\"requestId\":\"1\",\"operation\":\"get-appearance\",\"status\":\"success\",\"data\":{\"version\":1}}",
        ThawFixture.envelope(requestId: "1", data: ThawFixture.payload(scheme: "sepia")),
        ThawFixture.envelope(requestId: "1", data: ThawFixture.payload(tint: "{\"kind\":\"solid\"}")),
        ThawFixture.envelope(requestId: "1", data: ThawFixture.payload(tint: "\"solid\"")),
    ])
    func aMalformedBodyIsRejected(body: String) {
        #expect(throws: ThawAppearanceResponse.Rejection.malformed) {
            try ThawAppearanceResponse.appearance(in: Data(body.utf8))
        }
    }

    @Test func theAnswerIsReadFromTheDataParameterOfTheCallback() throws {
        let url = try ThawFixture.callback(ThawFixture.documented)
        let body = try #require(ThawAppearanceResponse.body(of: url))
        #expect(ThawAppearanceResponse.header(of: body)?.requestId == "5")
        #expect(try ThawAppearanceResponse.body(of: #require(URL(string: "floe://thaw-appearance"))) == nil)
    }
}

struct ThawAppearanceMappingTests {
    private func mirror(tint: String = ThawFixture.none, background: String = ThawFixture.none, border: String? = nil, hasShadow: Bool = false) throws -> ThawMirror {
        try ThawFixture.appearance(ThawFixture.payload(tint: tint, background: background, border: border, hasShadow: hasShadow))
            .mirrored(over: own)
    }

    @Test func noTintAndNoBackgroundTurnTheLaunchersTintOff() throws {
        let mirror = try mirror()
        #expect(mirror.look.tint.kind == .none)
        #expect(mirror.followed.contains(.tint))
        #expect(mirror.unmirrored.isEmpty)
    }

    @Test func aSolidTintBecomesASolidTintWithItsColourAndOpacity() throws {
        let mirror = try mirror(tint: ThawFixture.solidTint)
        #expect(mirror.look.tint.kind == .solid)
        #expect(mirror.look.tint.solid == StoredColor(.init(red: 1, green: 0.5, blue: 0, alpha: 1)))
        #expect(mirror.look.tint.opacity == 0.4)
        #expect(mirror.followed.contains(.tint))
    }

    @Test func aGradientKeepsItsFirstAndLastStopsAndRunsLeadingToTrailing() throws {
        let threeStops = """
        {"kind":"gradient","opacity":0.8,"stops":[
          {"color":{"red":0,"green":1,"blue":0,"alpha":1},"location":0.5},
          {"color":{"red":0,"green":0,"blue":1,"alpha":1},"location":1},
          {"color":{"red":1,"green":0,"blue":0,"alpha":1},"location":0}]}
        """
        let tint = try mirror(tint: threeStops).look.tint
        #expect(tint.kind == .gradient)
        #expect(tint.gradient.start == StoredColor(.init(red: 1, green: 0, blue: 0, alpha: 1)), "the stop at 0, wherever it is listed")
        #expect(tint.gradient.end == StoredColor(.init(red: 0, green: 0, blue: 1, alpha: 1)))
        #expect(tint.gradient.angle == 90, "Thaw's gradient runs along the menu bar, and 0 here is top to bottom")
        #expect(tint.opacity == 0.8)
    }

    @Test func aBackgroundIsTheTintWhenThawHasNoTintOfItsOwn() throws {
        let mirror = try mirror(background: ThawFixture.gradient)
        #expect(mirror.look.tint.kind == .gradient)
        #expect(mirror.look.tint.gradient.start == StoredColor(.init(red: 1, green: 0, blue: 0, alpha: 1)))
        #expect(mirror.look.tint.opacity == 1)
        #expect(try self.mirror(tint: ThawFixture.solidTint, background: ThawFixture.gradient).look.tint.kind == .solid, "the tint is drawn over the background")
    }

    @Test func aGlassBecomesTheLaunchersGlassWithItsStyle() throws {
        let mirror = try mirror(background: ThawFixture.clearGlass)
        #expect(mirror.look.glass.style == .clear)
        #expect(mirror.look.glass.followsSystem == false)
        #expect(mirror.look.glass.isColored == false)
        #expect(mirror.followed.contains(.glass))
        #expect(mirror.look.tint.kind == .none, "a glass is not a tint")
    }

    @Test func aColouredGlassBringsItsColourAndOpacity() throws {
        let glass = try mirror(tint: ThawFixture.coloredGlass).look.glass
        #expect(glass.style == .liquid)
        #expect(glass.isColored)
        #expect(glass.color == StoredColor(.init(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)))
        #expect(glass.opacity == 0.5)
    }

    @Test func withoutAGlassInThawTheLaunchersGlassStaysItsOwn() throws {
        let mirror = try mirror(tint: ThawFixture.solidTint)
        #expect(mirror.look.glass == own.glass)
        #expect(!mirror.followed.contains(.glass))
    }

    @Test(arguments: [ThawFixture.adaptive, ThawFixture.adaptiveGradient])
    func anAdaptiveTintLeavesTheLaunchersTintAloneAndIsNamed(fill: String) throws {
        let mirror = try mirror(tint: fill, background: ThawFixture.gradient)
        #expect(mirror.look.tint == own.tint)
        #expect(!mirror.followed.contains(.tint))
        #expect(mirror.unmirrored == [.tint])
    }

    @Test func anAdaptiveBackgroundLeavesTheLaunchersTintAloneAndIsNamed() throws {
        let mirror = try mirror(background: ThawFixture.adaptive)
        #expect(mirror.look.tint == own.tint)
        #expect(!mirror.followed.contains(.tint))
        #expect(mirror.unmirrored == [.background])
        let underATint = try self.mirror(tint: ThawFixture.solidTint, background: ThawFixture.adaptive)
        #expect(underATint.look.tint.kind == .solid)
        #expect(underATint.unmirrored == [.background], "still named, though the tint over it is followed")
    }

    @Test func aKindAddedLaterIsTreatedLikeAnAdaptiveOne() throws {
        let mirror = try mirror(tint: "{\"kind\":\"mesh\",\"opacity\":1}")
        #expect(mirror.look.tint == own.tint)
        #expect(mirror.unmirrored == [.tint])
    }

    @Test func aBorderInThePayloadIsDrawnWithItsColourAndWidth() throws {
        let mirror = try mirror(border: ThawFixture.dashedBorder)
        #expect(mirror.look.border == LauncherBorder(color: StoredColor(.init(red: 1, green: 1, blue: 1, alpha: 0.5)), width: 2))
        #expect(mirror.followed.contains(.border))
    }

    @Test func noBorderInThePayloadMeansNoBorder() throws {
        let mirror = try mirror()
        #expect(mirror.look.border == nil, "the launcher's own border is on")
        #expect(mirror.followed.contains(.border))
    }

    @Test(arguments: [true, false])
    func theShadowIsThaws(hasShadow: Bool) throws {
        let mirror = try mirror(hasShadow: hasShadow)
        #expect(mirror.look.hasShadow == hasShadow)
        #expect(mirror.followed.contains(.shadow))
    }

    @Test func opacityAndComponentsOutsideZeroToOneAreClamped() throws {
        let loud = "{\"kind\":\"solid\",\"opacity\":3,\"color\":{\"red\":2,\"green\":-1,\"blue\":0.5,\"alpha\":1}}"
        let tint = try mirror(tint: loud).look.tint
        #expect(tint.opacity == 1)
        #expect(tint.solid == StoredColor(.init(red: 1, green: 0, blue: 0.5, alpha: 1)))
    }

    @Test func theSettingsNoteNamesWhatFollowsTheWallpaper() throws {
        let lines = try ThawAppearanceNote.lines(status: .following, mirror: mirror(tint: ThawFixture.adaptive))
        #expect(lines == ["Thaw's tint follows the wallpaper, which the launcher cannot copy, so the launcher keeps its own tint."])
        #expect(try ThawAppearanceNote.lines(status: .following, mirror: mirror(tint: ThawFixture.solidTint)).isEmpty)
        let silent = ThawAppearanceNote.lines(status: .noAnswer, mirror: nil)
        #expect(silent.count == 1)
        #expect(silent.first?.contains("Allow Floe to Change Thaw Settings") == true)
    }
}

/// Stands in for Thaw and the clock: records what was opened and holds the timeouts until a test fires them.
private final class FakeThaw {
    var opened: [URL] = []
    var isRunning = true
    var now = Date(timeIntervalSince1970: 1000)
    var timeouts: [() -> Void] = []
    private var issued = 0

    var environment: ThawAppearanceFollower.Environment {
        .init(
            open: { self.opened.append($0)
                return true
            },
            isThawRunning: { self.isRunning },
            newRequestId: { self.issued += 1
                return "request-\(self.issued)"
            },
            now: { self.now },
            schedule: { _, work in self.timeouts.append(work) }
        )
    }

    func answer(_ requestId: String, tint: String = ThawFixture.solidTint, scheme: String = "dark") throws -> URL {
        try ThawFixture.callback(ThawFixture.envelope(requestId: requestId, data: ThawFixture.payload(scheme: scheme, tint: tint)))
    }
}

struct ThawAppearanceFollowerTests {
    private let scratch: ScratchDefaults
    private let settings: AppSettings
    private let thaw = FakeThaw()
    private let follower: ThawAppearanceFollower

    init() throws {
        scratch = try ScratchDefaults()
        settings = AppSettings(defaults: scratch.defaults)
        settings.followsThawAppearance = true
        follower = ThawAppearanceFollower(settings: settings, defaults: scratch.defaults, environment: thaw.environment)
    }

    @Test func theRequestIsTheLinkThawDocuments() {
        follower.refresh()
        #expect(thaw.opened.map(\.absoluteString) == ["thaw://get-appearance?callback=floe://thaw-appearance&requestId=request-1"])
    }

    @Test func theLiveRequestIdIsDifferentEveryTime() {
        let ids = (0 ..< 50).map { _ in ThawAppearanceFollower.Environment.live.newRequestId() }
        #expect(Set(ids).count == 50)
        #expect(ids.allSatisfy { UUID(uuidString: $0) != nil })
    }

    @Test func nothingIsAskedWhileTheSwitchIsOff() {
        settings.followsThawAppearance = false
        follower.refresh()
        #expect(thaw.opened.isEmpty)
        #expect(follower.status == .idle)
    }

    @Test func anAnswerToThePendingRequestIsKeptForItsScheme() throws {
        follower.refresh()
        try follower.receive(thaw.answer("request-1"))
        #expect(follower.status == .following)
        #expect(settings.thawAppearances[.dark]?.tint.kind == "solid")
        #expect(settings.launcherLook(for: .dark).tint.kind == .solid)
        #expect(settings.launcherTintLight.kind == .none, "the user's own settings are not written")
    }

    @Test func anAnswerWithAnotherRequestIdIsDropped() throws {
        follower.refresh()
        try follower.receive(thaw.answer("request-2"))
        try follower.receive(thaw.answer(""))
        #expect(settings.thawAppearances.isEmpty)
        #expect(follower.status == .idle)
        try follower.receive(thaw.answer("request-1"))
        #expect(settings.thawAppearances.count == 1, "the real answer still lands")
    }

    @Test func anAnswerNobodyAskedForIsDropped() throws {
        try follower.receive(thaw.answer("request-1"))
        #expect(settings.thawAppearances.isEmpty)
    }

    @Test func aRequestIdIsUsedOnce() throws {
        follower.refresh()
        try follower.receive(thaw.answer("request-1"))
        try follower.receive(thaw.answer("request-1", tint: ThawFixture.gradient))
        #expect(settings.thawAppearances[.dark]?.tint.kind == "solid", "the replay changed nothing")
    }

    @Test func anAnswerForAnotherOperationIsDropped() throws {
        follower.refresh()
        try follower.receive(ThawFixture.callback(ThawFixture.envelope(requestId: "request-1", operation: "list-items")))
        #expect(settings.thawAppearances.isEmpty)
        #expect(follower.status == .idle)
    }

    @Test func aLateAnswerAfterTheTimeoutIsDropped() throws {
        follower.refresh()
        thaw.now += ThawAppearanceFollower.timeout
        try follower.receive(thaw.answer("request-1"))
        #expect(settings.thawAppearances.isEmpty, "past the deadline, before the timer has fired")
        thaw.timeouts.forEach { $0() }
        #expect(follower.status == .noAnswer)
        try follower.receive(thaw.answer("request-1"))
        #expect(settings.thawAppearances.isEmpty)
    }

    @Test func whenThawDoesNotAnswerTheLastLookStaysAndTheSilenceIsRecorded() throws {
        follower.refresh()
        try follower.receive(thaw.answer("request-1"))
        follower.refresh()
        thaw.timeouts.forEach { $0() }
        #expect(follower.status == .noAnswer)
        #expect(settings.launcherLook(for: .dark).tint.kind == .solid)
    }

    @Test func anUnreadableAnswerChangesNothingButEndsTheRequest() throws {
        follower.refresh()
        try follower.receive(thaw.answer("request-1"))
        follower.refresh()
        try follower.receive(ThawFixture.callback(ThawFixture.envelope(requestId: "request-2", data: ThawFixture.payload(version: 2))))
        #expect(follower.status == .unreadable)
        #expect(settings.thawAppearances[.dark]?.tint.kind == "solid")
        try follower.receive(thaw.answer("request-2", tint: ThawFixture.gradient))
        #expect(settings.thawAppearances[.dark]?.tint.kind == "solid", "its id is spent")
    }

    @Test func aSecondFetchWaitsForTheOneInFlight() throws {
        follower.refresh()
        follower.refresh()
        follower.refresh()
        #expect(thaw.opened.count == 1)
        try follower.receive(thaw.answer("request-1"))
        #expect(thaw.opened.count == 2, "what arrived meanwhile is fetched once, after the answer")
        try follower.receive(thaw.answer("request-2"))
        #expect(thaw.opened.count == 2)
    }

    @Test func thawIsNotStartedJustToBeAsked() {
        thaw.isRunning = false
        follower.refresh()
        #expect(thaw.opened.isEmpty)
        #expect(follower.status == .notRunning)
    }

    @Test func eachSchemeKeepsItsOwnLookAndTheOtherStandsInUntilThen() throws {
        follower.refresh()
        try follower.receive(thaw.answer("request-1", tint: ThawFixture.solidTint, scheme: "dark"))
        #expect(settings.launcherLook(for: .light).tint.kind == .solid, "the dark look until Thaw answers for light")
        follower.refresh()
        try follower.receive(thaw.answer("request-2", tint: ThawFixture.gradient, scheme: "light"))
        #expect(settings.launcherLook(for: .light).tint.kind == .gradient)
        #expect(settings.launcherLook(for: .dark).tint.kind == .solid)
    }

    @Test func turningTheSwitchOffBringsBackTheUsersOwnLook() throws {
        settings.launcherTintLight = LauncherTint(kind: .gradient, opacity: 0.7)
        settings.launcherGlass = LauncherGlass(style: .dynamic)
        settings.launcherShowsBorder = true
        settings.launcherBorder = LauncherBorder(width: 3)
        let before = settings.ownLauncherLook(for: .dark)
        follower.refresh()
        try follower.receive(ThawFixture.callback(ThawFixture.envelope(
            requestId: "request-1",
            data: ThawFixture.payload(tint: ThawFixture.solidTint, background: ThawFixture.clearGlass, hasShadow: true)
        )))
        #expect(settings.launcherLook(for: .dark) != before)
        #expect(settings.thawMirror(for: .dark)?.followed == [.glass, .tint, .border, .shadow])
        settings.followsThawAppearance = false
        #expect(settings.launcherLook(for: .dark) == before)
        #expect(settings.thawMirror(for: .dark) == nil)
    }

    @Test func theLastAnswersComeBackAfterARelaunch() throws {
        follower.refresh()
        try follower.receive(thaw.answer("request-1"))
        let relaunched = AppSettings(defaults: scratch.defaults)
        relaunched.followsThawAppearance = true
        _ = ThawAppearanceFollower(settings: relaunched, defaults: scratch.defaults, environment: thaw.environment)
        #expect(relaunched.launcherLook(for: .dark).tint.kind == .solid)
    }
}

struct IncomingURLRouterTests {
    private final class Received {
        var appearance: [URL] = []
        var oauth: [URL] = []
    }

    private func router(oauthIsParked: Bool? = nil, _ received: Received) -> IncomingURLRouter {
        let appearance: (URL) -> Void = { received.appearance.append($0) }
        let oauth: (URL) -> Void = { received.oauth.append($0) }
        guard let oauthIsParked else { return IncomingURLRouter(appearance: appearance, oauth: oauth) }
        return IncomingURLRouter(oauthIsParked: oauthIsParked, appearance: appearance, oauth: oauth)
    }

    @Test func theAppearanceHostGoesToTheReceiver() throws {
        let received = Received()
        let url = try ThawFixture.callback(ThawFixture.documented)
        router(received).route(url)
        try router(received).route(#require(URL(string: "FLOE://Thaw-Appearance?data=x")))
        #expect(received.appearance.count == 2)
        #expect(received.appearance.first == url)
        #expect(received.oauth.isEmpty)
    }

    @Test(arguments: ["floe://settings", "floe://", "floe:thaw-appearance", "thaw://thaw-appearance", "https://thaw-appearance/", "floe://run?command=x"])
    func anyOtherLinkIsIgnored(link: String) throws {
        let received = Received()
        try router(oauthIsParked: false, received).route(#require(URL(string: link)))
        #expect(received.appearance.isEmpty)
        #expect(received.oauth.isEmpty)
    }

    @Test func anOAuthLinkDoesNothingWhileSignInIsParked() throws {
        #expect(OAuthBroker.isParked, "sign-in is parked; when it comes back this test changes with it")
        let received = Received()
        try router(received).route(#require(URL(string: "floe://oauth?state=a&package_name=b")))
        #expect(received.oauth.isEmpty)
        #expect(received.appearance.isEmpty)
    }

    @Test func anOAuthLinkReachesTheBrokerOnceSignInIsBack() throws {
        let received = Received()
        try router(oauthIsParked: false, received).route(#require(URL(string: "floe://oauth?state=a&package_name=b")))
        #expect(received.oauth.count == 1)
    }

    @Test func theAppRegistersTheFloeScheme() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist) as? [String: Any])
        let types = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
        #expect(types.first?["CFBundleURLName"] as? String == "org.thaw.floe")
        #expect(types.first?["CFBundleURLSchemes"] as? [String] == ["floe"])
    }
}

struct ThawAppearanceSettingTests {
    private let scratch: ScratchDefaults

    init() throws {
        scratch = try ScratchDefaults()
    }

    @Test func followingThawIsOffUntilItIsChosen() {
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.followsThawAppearance == false)
        #expect(settings.thawMirror(for: .light) == nil)
    }

    @Test func settingsSavedBeforeTheSwitchExistedStillLoad() {
        let old = """
        {"commandHotkeys":{},"aliases":{"hacker-news/frontpage":"hn"},"disabledExtensions":[],"includeRaycastExtensions":true,
         "launcherShowsShadow":true}
        """
        scratch.defaults.set(Data(old.utf8), forKey: "settings")
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.aliases == ["hacker-news/frontpage": "hn"])
        #expect(settings.launcherShowsShadow)
        #expect(settings.followsThawAppearance == false)
    }

    @Test func whatThawAnsweredIsNotSavedWithTheSettings() throws {
        let settings = AppSettings(defaults: scratch.defaults)
        settings.followsThawAppearance = true
        settings.thawAppearances[.dark] = try ThawFixture.appearance(ThawFixture.payload(tint: ThawFixture.solidTint))
        let exported = try String(decoding: settings.exportedJSON(), as: UTF8.self)
        #expect(exported.contains("followsThawAppearance"))
        #expect(!exported.contains("thawAppearances"))
        #expect(AppSettings(defaults: scratch.defaults).thawAppearances.isEmpty)
    }

    @Test func theSwitchCanBeFoundInTheSettingsSearch() {
        #expect(SearchIndex.appearanceEntries.contains { $0.id == "appearance.followThaw" })
    }
}
