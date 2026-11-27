//
//  OnboardingRenderTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import SwiftUI
import Testing
import ThawUI

/// Each page of the welcome drawn as the window draws it, on permissions that never reach the system.
@MainActor
struct OnboardingRenderTests {
    private func permission(required: Bool, granted: Bool) -> Permission {
        Permission(
            key: required ? "required" : "optional",
            title: required ? "Accessibility" : "Contacts",
            iconName: "star",
            iconColor: .blue,
            details: ["One detail"],
            declinedHint: "Turn it on in System Settings.",
            isRequired: required,
            settingsURL: nil,
            check: { granted },
            request: { completion in completion(false, true) },
            openURL: { _ in /* Nothing opens in a test. */ },
            pollInterval: 3600
        )
    }

    private func permissions(granted: Bool) -> AppPermissions {
        AppPermissions(accessibility: permission(required: true, granted: granted), others: [permission(required: false, granted: false)])
    }

    /// The page's size as the window takes it: as wide as the window, as tall as what it holds. The content's
    /// height is measured as it lays out, so the page settles over a few passes.
    private func size(of page: some View) async -> NSSize {
        let view = NSHostingView(rootView: page.thawTheme(.floe))
        for _ in 0 ..< 5 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return view.fittingSize
    }

    @Test(arguments: [false, true])
    func everyPageIsAsWideAsTheWindowAndAsTallAsItsContent(isReplay: Bool) async {
        let settings = AppSettings(defaults: MemoryDefaults(), savesAfterEdits: false)
        let pages: [AnyView] = [
            AnyView(OnboardingWelcomeView(isReplay: isReplay, onContinue: {}, onClose: {})),
            AnyView(ThawPermissionsView(permissions: permissions(granted: isReplay), isReplay: isReplay, onContinue: {}, onClose: {})),
            AnyView(OnboardingDoneView(settings: settings, finishTitle: "Open Floe", importFromRaycast: {}, onFinish: {})),
            AnyView(ThawOnboardingView(settings: settings, permissions: permissions(granted: false), isReplay: isReplay, importFromRaycast: {}, onFinish: {}, onClose: {})),
        ]
        for page in pages {
            let size = await size(of: page)
            #expect(size.width == ThawOnboardingWindowMetrics.width)
            #expect(size.height > 100 && size.height < 800)
        }
    }

    @Test func aPageTallerThanTheScreenAllowsScrollsAndKeepsItsButtonsInReach() async {
        let page = OnboardingPage {
            Color.clear.frame(height: 5000)
        } footer: {
            Button("Continue") {}
        }
        let limit = OnboardingPage<Color, Button<Text>>.contentLimit(screenHeight: NSScreen.main?.visibleFrame.height)
        let height = await size(of: page).height
        #expect(height > limit && height < limit + 120, "the content stops at the limit and the button bar stays below it")
        #expect(OnboardingPage<Color, Button<Text>>.contentLimit(screenHeight: 800) == 620)
        #expect(OnboardingPage<Color, Button<Text>>.contentLimit(screenHeight: 300) == 240, "a tiny screen still shows some content")
        #expect(OnboardingPage<Color, Button<Text>>.contentLimit(screenHeight: nil) == 620)
    }

    @Test func theWindowFollowsThePageFromOneHeightToTheNext() async {
        let page = PageHeight()
        let window = OnboardingWindowController.makeWindow(for: PageOfHeight(page: page))
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var heights: [CGFloat] = []
        for height in [200.0, 500, 300] {
            page.height = height
            for _ in 0 ..< 10 {
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(5))
            }
            heights.append(window.frame.height)
        }
        // The whole window, title bar included: a page that stopped short would leave a clear band above the bottom corners.
        #expect(heights == [200, 500, 300])
        #expect(window.frame.width == ThawOnboardingWindowMetrics.width)
    }

    @Test func theAccessButtonSaysWhatIsLeftOutAndEndsRecoveryWithTheFlowsLastWord() {
        #expect(ThawPermissionsView.continueTitle(state: .missing, finishTitle: nil) == "Continue Without Accessibility")
        #expect(ThawPermissionsView.continueTitle(state: .hasAll, finishTitle: nil) == "Continue")
        #expect(ThawPermissionsView.continueTitle(state: .hasAll, finishTitle: "Done") == "Done")
    }
}

/// A page whose height a test sets, standing in for the pages of the flow.
@MainActor @Observable
private final class PageHeight {
    var height: CGFloat = 200
}

private struct PageOfHeight: View {
    let page: PageHeight

    var body: some View {
        Color.clear.frame(width: ThawOnboardingWindowMetrics.width, height: page.height)
    }
}
